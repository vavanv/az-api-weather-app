# deploy-to-aca.ps1
$RESOURCE_GROUP = "rg-weatherapi-prod"
$LOCATION       = "eastus"
$APP_NAME       = "weatherapi"

# Generate unique ACR name (must be lowercase, 5-50 chars, alphanumeric only)
$random = Get-Random -Minimum 10000 -Maximum 99999
$ACR_NAME = "weatherapi$random".ToLower()   # e.g. weatherapi73842

$IMAGE = "$ACR_NAME.azurecr.io/$APP_NAME:latest"

Write-Host "Deploying $APP_NAME to Azure Container Apps..." -ForegroundColor Cyan
Write-Host "Using ACR name: $ACR_NAME" -ForegroundColor Magenta

# Login check
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) { az login }

# Register required providers (only slow the first time)
Write-Host "Registering resource providers..." -ForegroundColor Yellow
az provider register --namespace Microsoft.ContainerRegistry --wait --output none
az provider register --namespace Microsoft.App               --wait --output none
az provider register --namespace Microsoft.OperationalInsights --wait --output none

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

# Check ACR name availability
Write-Host "Checking if ACR name $ACR_NAME is available..." -ForegroundColor Green
$nameAvailable = az acr check-name --name $ACR_NAME --query "nameAvailable" -o tsv
if ($nameAvailable -ne "true") {
    Write-Error "ACR name $ACR_NAME is already taken. Run the script again — it will pick a new one."
    exit 1
}

# Create ACR
Write-Host "Creating Azure Container Registry $ACR_NAME..." -ForegroundColor Green
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true --output none

# Login to ACR
az acr login --name $ACR_NAME

# Get admin credentials
$json = az acr credential show --name $ACR_NAME --query "{username:username, password:passwords[0].value}" --output json
$cred = $json | ConvertFrom-Json
$acrUsername = $cred.username
$acrPassword = $cred.password

# Build and push image
Write-Host "Building and pushing image -> $IMAGE" -ForegroundColor Green
az acr build --registry $ACR_NAME --image "$APP_NAME:latest" --file Dockerfile .

# Deploy / update Container App
Write-Host "Deploying Container App $APP_NAME..." -ForegroundColor Green
az containerapp up `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --image $IMAGE `
    --registry-server "$ACR_NAME.azurecr.io" `
    --registry-username $acrUsername `
    --registry-password $acrPassword `
    --target-port 8080 `
    --ingress external `
    --env-vars "ASPNETCORE_ENVIRONMENT=Production" `
    --min-replicas 1 `
    --max-replicas 3

# Get URL
$url = az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query "properties.configuration.ingress.fqdn" -o tsv 2>$null

if ($url) {
    Write-Host "LIVE -> https://$url/swagger" -ForegroundColor Yellow
    Write-Host "Deployment successful!" -ForegroundColor Cyan
} else {
    Write-Host "Deployment in progress. Check Azure Portal -> Container Apps -> $APP_NAME in 1-2 minutes." -ForegroundColor Yellow
}