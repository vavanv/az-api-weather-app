# deploy-to-aca.ps1
param (
    [string]$ResourceGroup = "weather-rg",
    [string]$Location      = "eastus",
    [string]$AppName       = "weather-api",
    [string]$AcrName       = "arcforweatherapiweb",
    [string]$EnvName       = "weatherapi-env"
)

$ErrorActionPreference = "Stop"

# --- Helper Functions ---
function Get-Timestamp { return Get-Date -Format "yyyyMMddHHmm" }

# --- Main Script ---

Write-Host "Starting deployment for $AppName in $ResourceGroup ($Location)..." -ForegroundColor Cyan

# 1. Login to Azure
Write-Host "Checking Azure login..." -ForegroundColor Gray
$currentSub = az account list --query "[?isDefault].id" -o tsv
if ([string]::IsNullOrEmpty($currentSub)) {
    Write-Host "Please login to Azure..." -ForegroundColor Yellow
    az login
}

# 2. Register Providers
Write-Host "Ensuring resource providers are registered..." -ForegroundColor Gray
az provider register --namespace Microsoft.ContainerRegistry --wait --output none
az provider register --namespace Microsoft.App               --wait --output none
az provider register --namespace Microsoft.OperationalInsights --wait --output none

# 3. Create Resource Group
Write-Host "Ensuring Resource Group $ResourceGroup exists..." -ForegroundColor Gray
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create/check Resource Group $ResourceGroup"; exit 1 }

# 4. Handle ACR (Idempotency)
if ([string]::IsNullOrEmpty($AcrName)) {
    Write-Host "No ACR name provided. Checking for existing ACR in $ResourceGroup..." -ForegroundColor Gray
    $existingAcr = az acr list --resource-group $ResourceGroup --query "[0].name" -o tsv 2>$null

    if (-not [string]::IsNullOrEmpty($existingAcr)) {
        $AcrName = $existingAcr
        Write-Host "Found existing ACR: $AcrName" -ForegroundColor Cyan
    } else {
        $random = Get-Random -Minimum 10000 -Maximum 99999
        $AcrName = "weatherapi$random".ToLower()
        Write-Host "No existing ACR found. Creating new ACR: $AcrName" -ForegroundColor Yellow
        az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true --output none
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create ACR $AcrName"; exit 1 }
    }
} else {
    Write-Host "Using provided ACR: $AcrName" -ForegroundColor Cyan
    $acrCheck = az acr list --resource-group $ResourceGroup --query "[?name=='$AcrName'].name" -o tsv
    if ([string]::IsNullOrEmpty($acrCheck)) {
        Write-Host "ACR $AcrName does not exist. Creating..." -ForegroundColor Yellow
        az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true --output none
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create ACR $AcrName"; exit 1 }
    }
}

# Login to ACR
az acr login --name $AcrName
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to login to ACR $AcrName"; exit 1 }

# 5. Build and Push Image (Local Docker vs ACR Build)
$timestamp = Get-Timestamp
$imageTag  = "$AcrName.azurecr.io/$($AppName):$timestamp"
$latestTag = "$AcrName.azurecr.io/$($AppName):latest"

Write-Host "Preparing to build image..." -ForegroundColor Green
if (Get-Command "docker" -ErrorAction SilentlyContinue) {
    Write-Host "Local Docker detected. Using local build..." -ForegroundColor Cyan

    # Build
    docker build -t $imageTag -t $latestTag .
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed"; exit 1 }

    # Push
    Write-Host "Pushing images to ACR..." -ForegroundColor Cyan
    docker push $imageTag
    docker push $latestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker push failed"; exit 1 }

} else {
    Write-Warning "Docker not found locally. Falling back to 'az acr build' (may fail if Tasks are blocked)..."
    az acr build --registry $AcrName --image $imageTag --image $latestTag --file Dockerfile .
}

# 6. Get ACR Credentials
$cred = az acr credential show --name $AcrName --output json | ConvertFrom-Json
$acrUsername = $cred.username
$acrPassword = $cred.passwords[0].value

# 7. Create/Update Log Analytics Workspace
$LogAnalyticsName = "$AppName-logs"
Write-Host "Ensuring Log Analytics Workspace $LogAnalyticsName..." -ForegroundColor Green
$existingWs = az monitor log-analytics workspace list --resource-group $ResourceGroup --query "[?name=='$LogAnalyticsName'].name" -o tsv
if ([string]::IsNullOrEmpty($existingWs)) {
    Write-Host "Creating Log Analytics Workspace..." -ForegroundColor Yellow
    az monitor log-analytics workspace create --resource-group $ResourceGroup --workspace-name $LogAnalyticsName --location $Location --output none
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Log Analytics Workspace $LogAnalyticsName"; exit 1 }
}

$logsCustomerId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $LogAnalyticsName --query customerId --output tsv
$logsKey        = az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $LogAnalyticsName --query primarySharedKey --output tsv

# 8. Create/Update Container App Environment (with quota handling)

Write-Host "Ensuring Container Apps Environment $EnvName..." -ForegroundColor Green

# Check if environment already exists across the subscription
$existingEnvJson = az containerapp env list --query "[?name=='$EnvName']" -o json
$existingEnv = $existingEnvJson | ConvertFrom-Json

if ($existingEnv -and $existingEnv.Count -gt 0) {
    $envLocation = $existingEnv[0].location
    $envRg = $existingEnv[0].resourceGroup

    # Normalize locations for comparison (Azure returns "East US", we use "eastus")
    $normalizedEnvLocation = $envLocation.ToLower() -replace '\s', ''
    $normalizedTargetLocation = $Location.ToLower() -replace '\s', ''

    if ($normalizedEnvLocation -eq $normalizedTargetLocation -and $envRg -eq $ResourceGroup) {
        Write-Host "Found existing environment $EnvName in $ResourceGroup ($envLocation). Reusing it." -ForegroundColor Cyan
    } else {
        Write-Warning "Environment $EnvName exists in $envRg ($envLocation), but you're deploying to $ResourceGroup ($Location)."
        Write-Warning "Due to subscription quota limits (max 1 environment), you have two options:"
        Write-Warning "  1. Delete the old environment and retry: az containerapp env delete --name $EnvName --resource-group $envRg -y"
        Write-Warning "  2. Deploy to the existing location: .\deploy-to-aca.ps1 -Location '$envLocation' -ResourceGroup '$envRg'"
        Write-Error "Cannot proceed - environment exists in a different region/resource group."
        exit 1
    }
} else {
    # Environment doesn't exist, try to create it
    Write-Host "Creating new environment..." -ForegroundColor Yellow
    az containerapp env create `
        --name $EnvName `
        --resource-group $ResourceGroup `
        --location $Location `
        --logs-workspace-id $logsCustomerId `
        --logs-workspace-key $logsKey `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Container Apps Environment. This may be due to subscription quota limits."
        Write-Warning "List existing environments: az containerapp env list -o table"
        exit 1
    }
}

# Wait for provisioning
Write-Host "Waiting for environment to be ready..." -ForegroundColor Yellow
$timeoutSeconds = 180
$elapsed = 0
do {
    $envStatus = az containerapp env show --name $EnvName --resource-group $ResourceGroup --query "properties.provisioningState" -o tsv 2>$null
    if ($envStatus -eq "Succeeded") {
        Write-Host "Environment is ready!" -ForegroundColor Green
        break
    }

    if ($elapsed -ge $timeoutSeconds) {
        Write-Error "Timeout waiting for environment provisioning."
        exit 1
    }

    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Status: $envStatus (waited ${elapsed}s)" -ForegroundColor Gray
} while ($true)

# 9. Deploy Container App
Write-Host "Deploying Container App $AppName..." -ForegroundColor Green
az containerapp create `
    --name $AppName `
    --resource-group $ResourceGroup `
    --environment $EnvName `
    --image $imageTag `
    --registry-server "$AcrName.azurecr.io" `
    --registry-username $acrUsername `
    --registry-password $acrPassword `
    --target-port 8080 `
    --ingress external `
    --min-replicas 1 `
    --max-replicas 3 `
    --env-vars "ASPNETCORE_ENVIRONMENT=Production" `
    --query "properties.configuration.ingress.fqdn" -o tsv

# 10. Final Output
$url = az containerapp show --name $AppName --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv 2>$null
if (-not [string]::IsNullOrEmpty($url)) {
    Write-Host ""
    Write-Host "SUCCESS! Your Weather API is running." -ForegroundColor Cyan
    Write-Host "Swagger UI: https://$url/swagger" -ForegroundColor Yellow
} else {
    Write-Warning "Deployment finished, but URL could not be retrieved immediately."
}