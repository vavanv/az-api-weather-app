# Weather API 🌤️

A RESTful ASP.NET Core 8.0 Web API for weather forecasting with full CRUD operations, deployed to Azure Container Apps with automated CI/CD.

[![Deploy to Azure Container Apps](https://img.shields.io/badge/Azure-Container%20Apps-blue)](https://azure.microsoft.com/en-us/products/container-apps/)
[![.NET 8](https://img.shields.io/badge/.NET-8.0-purple)](https://dotnet.microsoft.com/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## 📋 Table of Contents

- [Features](#-features)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [API Endpoints](#-api-endpoints)
- [Getting Started](#-getting-started)
- [Local Development](#-local-development)
- [Deployment](#-deployment)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Configuration](#-configuration)

## ✨ Features

- **Full CRUD Operations**: Create, Read, Update, and Delete weather forecasts
- **Filtering & Querying**: Filter forecasts by date range and temperature
- **Statistics Endpoint**: Get aggregated weather statistics
- **Sample Data Generation**: Generate test forecasts on-demand
- **Swagger UI**: Interactive API documentation available in all environments
- **Docker Support**: Multi-stage Dockerfile for optimized container builds
- **Azure Container Apps**: Serverless, scalable container hosting
- **GitHub Actions CI/CD**: Automated deployments on push to main branch

## 🛠️ Tech Stack

| Technology               | Version     | Purpose                       |
| ------------------------ | ----------- | ----------------------------- |
| .NET                     | 8.0         | Runtime & Framework           |
| ASP.NET Core             | 8.0         | Web API Framework             |
| Swashbuckle              | 6.6.2       | Swagger/OpenAPI Documentation |
| Docker                   | Multi-stage | Containerization              |
| Azure Container Apps     | -           | Cloud Hosting                 |
| Azure Container Registry | -           | Container Image Storage       |
| GitHub Actions           | -           | CI/CD Pipeline                |

## 📁 Project Structure

```
WeatherApi/
├── Controllers/
│   └── WeatherForecastController.cs   # API controller with CRUD endpoints
├── Properties/
│   └── launchSettings.json            # Development launch profiles
├── .github/
│   └── workflows/
│       └── weather-api-*.yml          # GitHub Actions CI/CD workflow
├── Program.cs                         # Application entry point & configuration
├── WeatherApi.csproj                  # Project file with dependencies
├── Dockerfile                         # Multi-stage Docker build
├── deploy-to-aca.ps1                  # PowerShell deployment script
├── deploy-to-aca.sh                   # Bash deployment script
├── WeatherApi.http                    # HTTP test file for VS Code REST Client
└── README.md                          # This file
```

## 🔌 API Endpoints

### Weather Forecasts

| Method   | Endpoint                | Description                                 |
| -------- | ----------------------- | ------------------------------------------- |
| `GET`    | `/WeatherForecast`      | Get all forecasts (with optional filtering) |
| `GET`    | `/WeatherForecast/{id}` | Get a specific forecast by ID               |
| `POST`   | `/WeatherForecast`      | Create a new forecast                       |
| `PUT`    | `/WeatherForecast/{id}` | Update an existing forecast                 |
| `DELETE` | `/WeatherForecast/{id}` | Delete a forecast                           |

### Utilities

| Method | Endpoint                                    | Description               |
| ------ | ------------------------------------------- | ------------------------- |
| `GET`  | `/WeatherForecast/statistics/summary`       | Get weather statistics    |
| `POST` | `/WeatherForecast/generate-samples?count=5` | Generate sample forecasts |

### Query Parameters (GET /WeatherForecast)

| Parameter  | Type     | Description                      |
| ---------- | -------- | -------------------------------- |
| `fromDate` | DateOnly | Filter forecasts from this date  |
| `toDate`   | DateOnly | Filter forecasts until this date |
| `minTemp`  | int      | Minimum temperature (Celsius)    |
| `maxTemp`  | int      | Maximum temperature (Celsius)    |

### Request/Response Example

**Create Forecast (POST /WeatherForecast)**

```json
{
  "date": "2026-01-18",
  "temperatureC": 15,
  "summary": "Mild",
  "location": "Toronto, Canada"
}
```

**Response**

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "forecast": {
    "date": "2026-01-18",
    "temperatureC": 15,
    "summary": "Mild",
    "location": "Toronto, Canada"
  }
}
```

## 🚀 Getting Started

### Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Docker Desktop](https://www.docker.com/products/docker-desktop) (for containerization)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (for Azure deployment)

### Quick Start

```bash
# Clone the repository
git clone git@github.com:vavanv/az-api-weather-app.git
cd WeatherApi

# Run locally
dotnet run

# Open Swagger UI
# Navigate to: https://localhost:5001/swagger
```

## 💻 Local Development

### Running with .NET CLI

```bash
# Restore dependencies
dotnet restore

# Build the project
dotnet build

# Run the application
dotnet run

# Run with watch mode (hot reload)
dotnet watch run
```

### Running with Docker

```bash
# Build the Docker image
docker build -t weatherapi:local .

# Run the container
docker run -d -p 8080:8080 --name weatherapi weatherapi:local

# Access the API
curl http://localhost:8080/WeatherForecast

# View Swagger UI
# Navigate to: http://localhost:8080/swagger
```

## 🌐 Deployment

### Option 1: PowerShell Script (Windows)

```powershell
# Deploy with default settings
.\deploy-to-aca.ps1

# Deploy with custom parameters
.\deploy-to-aca.ps1 -ResourceGroup "my-rg" -Location "westus" -AppName "my-weather-api"
```

### Option 2: Bash Script (Linux/macOS)

```bash
# Deploy with default settings
./deploy-to-aca.sh

# Deploy with custom parameters
./deploy-to-aca.sh "my-rg" "westus" "my-weather-api"
```

### Deployment Script Parameters

| Parameter     | Default            | Description                   |
| ------------- | ------------------ | ----------------------------- |
| ResourceGroup | `weather-rg`       | Azure Resource Group name     |
| Location      | `eastus`           | Azure region                  |
| AppName       | `weather-api`      | Container App name            |
| AcrName       | _(auto-generated)_ | Azure Container Registry name |

### What the Deployment Scripts Do

1. **Check Prerequisites**: Verify Azure login and Docker installation
2. **Register Providers**: Ensure required Azure providers are registered
3. **Create Resource Group**: Create or verify the resource group exists
4. **Setup ACR**: Create or reuse Azure Container Registry
5. **Build & Push Image**: Build Docker image and push to ACR
6. **Create Log Analytics**: Setup monitoring workspace
7. **Create Environment**: Setup Container Apps environment
8. **Deploy Application**: Create or update the Container App
9. **Output URL**: Display the public Swagger UI URL

## 🔄 CI/CD Pipeline

The project includes a GitHub Actions workflow that automatically deploys to Azure Container Apps on every push to the `main` branch.

### Required GitHub Secrets

| Secret                             | Description                      |
| ---------------------------------- | -------------------------------- |
| `WEATHERAPI_AZURE_CLIENT_ID`       | Azure AD Application (client) ID |
| `WEATHERAPI_AZURE_TENANT_ID`       | Azure AD Tenant ID               |
| `WEATHERAPI_AZURE_SUBSCRIPTION_ID` | Azure Subscription ID            |
| `WEATHERAPI_REGISTRY_USERNAME`     | ACR username                     |
| `WEATHERAPI_REGISTRY_PASSWORD`     | ACR password                     |

### Workflow Triggers

- **Automatic**: Push to `main` branch
- **Manual**: Workflow dispatch from GitHub Actions UI

## ⚙️ Configuration

### Environment Variables

| Variable                 | Default         | Description      |
| ------------------------ | --------------- | ---------------- |
| `ASPNETCORE_ENVIRONMENT` | `Production`    | Environment name |
| `ASPNETCORE_URLS`        | `http://+:8080` | Listening URLs   |

### Default Behavior

- When no forecasts exist, the API returns default forecasts for **Richmond Hill, ON, Canada**
- In-memory storage is used (data is lost on restart) - use a database for production
- Swagger UI is enabled in all environments for easy API exploration

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

**Built with ❤️ using .NET 8 and Azure Container Apps**
