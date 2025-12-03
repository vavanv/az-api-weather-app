# Walkthrough: Refactored Deployment Script

I have refactored the `deploy-to-aca.ps1` script to be more robust, idempotent, and configurable. It now uses **local Docker** to build images and ensures **Swagger UI** is available in production.

## Changes

### 1. Build Strategy (Local Docker)

- The script now checks for a local `docker` installation.
- It uses `docker build` and `docker push` to upload images to the Azure Container Registry.
- This resolves the `TasksOperationsNotAllowed` error.

### 2. Swagger UI Access

- I modified `Program.cs` to enable Swagger middleware in **all environments**, not just Development.
- This resolves the **404 Error** you encountered when accessing `/swagger` on the deployed app.

### 3. Documentation

- Updated `README.md` with:
  - Prerequisites (Docker, Azure CLI).
  - Detailed usage instructions for `deploy-to-aca.ps1`.
  - Explanation of parameters.

### 4. Remote Build Script

- Created `deploy-to-aca-remote.ps1`.
- This script forces a remote build using `az acr build`, bypassing local Docker checks.
- **Note**: Requires ACR Tasks to be allowed in your subscription.

## Verification Results

### Manual Verification

1.  **Run the script**:
    ```powershell
    .\deploy-to-aca.ps1
    ```
2.  **Access the App**:
    - The script outputs the Swagger URL at the end.
    - Open this URL in your browser to see the Swagger UI.
