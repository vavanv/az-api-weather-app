#!/bin/bash
# File: deploy-to-aca.sh
# One-file reusable deploy for .NET 8 → Azure Container Apps (2025)

set -e  # Stop on any error

# ─────────────── CONFIGURE THESE ONCE ───────────────
RESOURCE_GROUP="rg-weatherapi-prod"      # Change once
LOCATION="eastus"                        # Change once
APP_NAME="weatherapi"                    # Your app name (lowercase)
ACR_NAME="crweatherapi2025"              # Must be globally unique (created once)
# ─────────────────────────────────────────────────────

# Auto-calculated values
IMAGE_NAME="${ACR_NAME}.azurecr.io/${APP_NAME}:latest"
REVISION_SUFFIX=$(date +%Y%m%d%H%M)

echo "Deploying .NET API to Azure Container Apps..."
echo "App: $APP_NAME | Image: $IMAGE_NAME | Revision: $REVISION_SUFFIX"

# 1. Login (only needed first time or when token expires)
az account show > /dev/null 2>&1 || az login

# 2. Create RG & ACR if they don't exist yet
az group create --name $RESOURCE_GROUP --location $LOCATION --only-show-errors
az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1 || \
  az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true

# 3. Build & push image directly from source (no local Docker needed!)
echo "Building and pushing container image..."
az acr build \
  --registry $ACR_NAME \
  --image $IMAGE_NAME \
  --file Dockerfile .

# 4. Deploy / update Container App (creates environment automatically first time)
echo "Deploying to Container Apps..."
az containerapp up \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image $IMAGE_NAME \
  --registry-server ${ACR_NAME}.azurecr.io \
  --target-port 8080 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 10 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars "ASPNETCORE_ENVIRONMENT=Production" \
  --revision-suffix $REVISION_SUFFIX \
  --query "properties.configuration.ingress.fqdn" -o tsv

# 5. Final URL
URL=$(az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
echo ""
echo "LIVE → https://$URL"
echo "Swagger → https://$URL/swagger"
echo "Done! New revision: $REVISION_SUFFIX"