# deploy-to-aca.ps1
param (
    [string]$ResourceGroup = "rg-weatherapi-prod",
    [string]$Location      = "eastus",
    [string]$AppName       = "weatherapi",
    [string]$AcrName       = ""
)

$ErrorActionPreference = "Stop"

# --- Helper Functions ---
function Get-Timestamp { return Get-Date -Format "yyyyMMddHHmm" }

# --- Main Script ---

Write-Host "Starting deployment for $AppName in $ResourceGroup ($Location)..." -ForegroundColor Cyan

# 1. Login to Azure
Write-Host "Checking Azure login..." -ForegroundColor Gray
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
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
    }
} else {
    Write-Host "Using provided ACR: $AcrName" -ForegroundColor Cyan
    $acrExists = az acr show --name $AcrName --resource-group $ResourceGroup --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ACR $AcrName does not exist. Creating..." -ForegroundColor Yellow
        az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true --output none
    }
}

# Login to ACR
az acr login --name $AcrName

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

# 7. Create/Update Container App Environment
$EnvName = "$AppName-env"
Write-Host "Ensuring Container Apps Environment $EnvName..." -ForegroundColor Green
az containerapp env create --name $EnvName --resource-group $ResourceGroup --location $Location --output none

# Wait for provisioning
Write-Host "Waiting for environment to be ready..." -ForegroundColor Yellow
$timeoutSeconds = 180
$elapsed = 0
do {
    $envStatus = az containerapp env show --name $EnvName --resource-group $ResourceGroup --query "properties.provisioningState" -o tsv
    if ($envStatus -eq "Succeeded") { break }

    if ($elapsed -ge $timeoutSeconds) {
        Write-Error "Timeout waiting for environment provisioning."
        exit 1
    }

    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Status: $envStatus (waited ${elapsed}s)" -ForegroundColor Gray
} while ($true)

# 8. Deploy Container App
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

# 9. Final Output
$url = az containerapp show --name $AppName --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv 2>$null
if (-not [string]::IsNullOrEmpty($url)) {
    Write-Host ""
    Write-Host "SUCCESS! Your Weather API is running." -ForegroundColor Cyan
    Write-Host "Swagger UI: https://$url/swagger" -ForegroundColor Yellow
} else {
    Write-Warning "Deployment finished, but URL could not be retrieved immediately."
}