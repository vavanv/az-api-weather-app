# Weather API

A simple ASP.NET Core Web API for weather forecasting, deployed to Azure Container Apps.

## Features

- **ASP.NET Core 8.0**: Modern, high-performance web framework.
- **Swagger UI**: Interactive API documentation available in all environments.
- **Azure Container Apps**: Serverless container hosting.
- **Automated Deployment**: PowerShell script for easy deployment.

## Prerequisites

- **Azure CLI**: [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Docker**: [Install Docker Desktop](https://www.docker.com/products/docker-desktop) (Required for building images)
- **PowerShell**: For running the deployment script.

## Deployment

The project includes a robust PowerShell script `deploy-to-aca.ps1` to automate deployment to Azure Container Apps.

### Usage

```powershell
.\deploy-to-aca.ps1 [options]
```

### Parameters

| Parameter        | Default              | Description                                                                               |
| :--------------- | :------------------- | :---------------------------------------------------------------------------------------- |
| `-ResourceGroup` | `rg-weatherapi-prod` | Azure Resource Group name.                                                                |
| `-Location`      | `eastus`             | Azure region.                                                                             |
| `-AppName`       | `weatherapi`         | Name of the Container App.                                                                |
| `-AcrName`       | _(Auto-generated)_   | Azure Container Registry name. If omitted, it finds an existing one or creates a new one. |

### Example

```powershell
# Deploy with default settings
.\deploy-to-aca.ps1

# Deploy to a specific group with a custom name
.\deploy-to-aca.ps1 -ResourceGroup "rg-my-project" -AppName "my-weather-api"
```

### How it Works

1.  **Checks Prerequisites**: Verifies Azure login and Docker installation.
2.  **Idempotency**: Checks for existing resources (ACR, Environment) to avoid duplicates.
3.  **Builds Image**: Uses local `docker build` to create the image.
4.  **Pushes Image**: Pushes the image to your Azure Container Registry (ACR).
5.  **Deploys App**: Creates or updates the Azure Container App with the new image.
6.  **Output**: Displays the public URL of the deployed API (Swagger UI).

## API Documentation

Once deployed, you can access the Swagger UI at:

```
https://<your-app-url>/swagger
```

The deployment script will print this URL upon success.
