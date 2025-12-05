#!/bin/bash
# File: deploy-to-aca.sh
# One-file reusable deploy for .NET 8 → Azure Container Apps (2025)

set -e  # Stop on any error

# Parameters
RESOURCE_GROUP="${1:-rg-weatherapi-prod-new}"
LOCATION="${2:-eastus}"
APP_NAME="${3:-weatherapi}"
ACR_NAME="${4}"

# Auto-calculated values
if [ -z "$ACR_NAME" ]; then
    # Check for existing ACR
    existing_acr=$(az acr list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$existing_acr" ]; then
        ACR_NAME="$existing_acr"
        echo "Found existing ACR: $ACR_NAME"
    else
        random=$((10000 + RANDOM % 90000))
        ACR_NAME="weatherapi${random}"
        echo "Creating new ACR: $ACR_NAME"
    fi
else
    echo "Using provided ACR: $ACR_NAME"
fi

TIMESTAMP=$(date +%Y%m%d%H%M)
IMAGE_TAG="${ACR_NAME}.azurecr.io/${APP_NAME}:${TIMESTAMP}"
LATEST_TAG="${ACR_NAME}.azurecr.io/${APP_NAME}:latest"

echo "Starting deployment for $APP_NAME in $RESOURCE_GROUP ($LOCATION)..."
echo "ACR: $ACR_NAME | Image: $IMAGE_TAG"

# 1. Login to Azure
current_sub=$(az account list --query "[?isDefault].id" -o tsv)
if [ -z "$current_sub" ]; then
    echo "Please login to Azure..."
    az login
fi

# 2. Register Providers
echo "Ensuring resource providers are registered..."
az provider register --namespace Microsoft.ContainerRegistry --wait --output none
az provider register --namespace Microsoft.App --wait --output none
az provider register --namespace Microsoft.OperationalInsights --wait --output none

# 4. Handle ACR
acr_check=$(az acr list --resource-group $RESOURCE_GROUP --query "[?name=='$ACR_NAME'].name" -o tsv)
if [ -z "$acr_check" ]; then
    echo "ACR $ACR_NAME does not exist. Creating..."
    az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true --output none
fi

# Login to ACR
az acr login --name $ACR_NAME

# 5. Build and Push Image
echo "Preparing to build image..."
if command -v docker >/dev/null 2>&1; then
    echo "Local Docker detected. Using local build..."
    docker build -t $IMAGE_TAG -t $LATEST_TAG .
    echo "Pushing images to ACR..."
    docker push $IMAGE_TAG
    docker push $LATEST_TAG
else
    echo "Docker not found. Using az acr build..."
    az acr build --registry $ACR_NAME --image $IMAGE_TAG --image $LATEST_TAG --file Dockerfile .
fi

# 6. Get ACR Credentials
acr_cred=$(az acr credential show --name $ACR_NAME --output json)
acr_username=$(echo $acr_cred | jq -r '.username')
acr_password=$(echo $acr_cred | jq -r '.passwords[0].value')

# 7. Create/Update Log Analytics Workspace
LOG_ANALYTICS_NAME="$APP_NAME-logs"
echo "Ensuring Log Analytics Workspace $LOG_ANALYTICS_NAME..."
existing_ws=$(az monitor log-analytics workspace list --resource-group $RESOURCE_GROUP --query "[?name=='$LOG_ANALYTICS_NAME'].name" -o tsv)
if [ -z "$existing_ws" ]; then
    echo "Creating Log Analytics Workspace..."
    az monitor log-analytics workspace create --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME --location $LOCATION --output none
fi
logs_customer_id=$(az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME --query customerId -o tsv)
logs_key=$(az monitor log-analytics workspace get-shared-keys --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME --query primarySharedKey -o tsv)

# 8. Create/Update Container App Environment
ENV_NAME="$APP_NAME-env"
echo "Ensuring Container Apps Environment $ENV_NAME..."
existing_env=$(az containerapp env list --query "[?name=='$ENV_NAME']" -o json)
if [ "$existing_env" != "[]" ]; then
    echo "Found existing environment $ENV_NAME. Reusing it."
else
    echo "Creating new environment..."
    az containerapp env create --name $ENV_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --logs-workspace-id $logs_customer_id --logs-workspace-key $logs_key --output none
fi

# Wait for provisioning
echo "Waiting for environment to be ready..."
timeout=180
elapsed=0
while [ $elapsed -lt $timeout ]; do
    env_status=$(az containerapp env show --name $ENV_NAME --resource-group $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>/dev/null)
    if [ "$env_status" = "Succeeded" ]; then
        echo "Environment is ready!"
        break
    fi
    if [ $elapsed -ge $timeout ]; then
        echo "Timeout waiting for environment provisioning."
        exit 1
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "Status: $env_status (waited ${elapsed}s)"
done

# 9. Deploy Container App
echo "Deploying Container App $APP_NAME..."
az containerapp create --name $APP_NAME --resource-group $RESOURCE_GROUP --environment $ENV_NAME --image $IMAGE_TAG --registry-server "$ACR_NAME.azurecr.io" --registry-username $acr_username --registry-password $acr_password --target-port 8080 --ingress external --min-replicas 1 --max-replicas 3 --env-vars "ASPNETCORE_ENVIRONMENT=Production" --query "properties.configuration.ingress.fqdn" -o tsv

# 10. Final Output
url=$(az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null)
if [ -n "$url" ]; then
    echo ""
    echo "SUCCESS! Your Weather API is running."
    echo "Swagger UI: https://$url/swagger"
else
    echo "Deployment finished, but URL could not be retrieved immediately."
fi
