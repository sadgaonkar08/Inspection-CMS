# Azure Deployment Guide - Complete Setup

This guide provides step-by-step instructions to deploy the ICMS Inspection application to Azure with a **NEW Azure account**, including all required resources, database setup, and nginx configuration.

## Architecture Overview

The application consists of:
- **Rails Application** (Ruby 3.2.2) running on port 3000
- **Nginx Web Server** handling SSL/TLS termination and reverse proxy
- **PostgreSQL Flexible Server** for database
- **Azure Container Registry** for Docker images
- **Azure App Service** for hosting the containerized application

Both nginx and Rails run in a single container managed by Supervisor.

## Prerequisites

- Azure CLI installed (`brew install azure-cli` on macOS)
- Docker installed locally
- Access to a NEW Azure subscription (not sadgaonkar account)
- Rails master key (stored in `config/master.key`)

---

## Step 0: Login to NEW Azure Account

**IMPORTANT:** This guide assumes you're using a NEW Azure account, NOT the sadgaonkar account.

### 0.1 Logout from Current Account (if any)

```bash
# Check current account
az account show

# Logout from current account
az logout
```

### 0.2 Login to NEW Azure Account

```bash
# Login to your new Azure account
az login

# This will open a browser window for authentication
# Login with your NEW Azure credentials
```

### 0.3 Verify Login

```bash
# List all subscriptions
az account list --output table

# Show current subscription
az account show --output table
```

### 0.4 Set the Correct Subscription (if you have multiple)

```bash
# If you have multiple subscriptions, set the one you want to use
az account set --subscription "YOUR_SUBSCRIPTION_NAME_OR_ID"

# Verify
az account show --query "{Name:name, ID:id, TenantID:tenantId}" --output table
```

---

## Step 1: Set Environment Variables

Set these variables in your terminal before starting:

```bash
export RESOURCE_GROUP="geometrics-icms-rg"
export LOCATION="westus3"
export APP_NAME="geometriceng-icms-inspection-app"
export ACR_NAME="geometricsicmsacr28feb26"  # Must be globally unique, lowercase alphanumeric only
export DB_SERVER="cms-inspection-flex-pg-db-server01"
export DB_NAME="cms_inspection_db"
export DB_ADMIN_USER="cms_inspection_dbadmin"
export DB_ADMIN_PASSWORD="Simba_4ever"  # Change this to a secure password
```

**IMPORTANT:** Change the values above to match your preferences, especially:
- `ACR_NAME` must be globally unique (try adding your initials or random numbers)
- `DB_ADMIN_PASSWORD` should be a strong, secure password

---

## Step 2: Create Azure Resource Group

Create a resource group to organize all Azure resources:

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

**Expected Output:**
```json
{
  "id": "/subscriptions/.../resourceGroups/geometrics-icms-rg",
  "location": "westus3",
  "name": "geometrics-icms-rg",
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

---

## Step 3: Create Azure Container Registry (ACR)

Create a container registry to store your Docker images:

```bash
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --location $LOCATION \
  --admin-enabled true
```

**Expected Output:**
```json
{
  "adminUserEnabled": true,
  "creationDate": "...",
  "loginServer": "geometricsicmsacr28feb26.azurecr.io",
  "name": "geometricsicmsacr28feb26",
  "provisioningState": "Succeeded",
  "sku": {
    "name": "Basic"
  }
}
```

---

## Step 4: Create PostgreSQL Flexible Server

### 4.1 Create PostgreSQL Server

```bash
az postgres flexible-server create \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER \
  --location $LOCATION \
  --admin-user $DB_ADMIN_USER \
  --admin-password $DB_ADMIN_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 14 \
  --storage-size 32 \
  --public-access 0.0.0.0-255.255.255.255
```

**Note:** The `public-access` setting allows connections from Azure services. For production, configure firewall rules to restrict access.

### 4.2 Create Database

```bash
az postgres flexible-server db create \
  --resource-group $RESOURCE_GROUP \
  --server-name $DB_SERVER \
  --database-name $DB_NAME
```

### 4.3 Configure PostgreSQL SSL

Set `require_secure_transport` to OFF to allow non-SSL connections:

```bash
az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $DB_SERVER \
  --name require_secure_transport \
  --value OFF
```

### 4.4 Get Database Connection String

```bash
export DB_HOST="${DB_SERVER}.postgres.database.azure.com"
export DATABASE_URL="postgresql://${DB_ADMIN_USER}:${DB_ADMIN_PASSWORD}@${DB_HOST}:5432/${DB_NAME}?sslmode=prefer"

echo "Database URL: $DATABASE_URL"
```

---

## Step 5: Build and Push Docker Image

### 5.1 Login to Azure Container Registry

```bash
az acr login --name $ACR_NAME
```

**Expected Output:**
```
Login Succeeded
```

### 5.2 Build Docker Image

Build the combined nginx + Rails image using `Dockerfile.combined`:

```bash
docker build -f Dockerfile.combined -t ${ACR_NAME}.azurecr.io/icms-inspection-app:latest .
```

This will:
- Build the Rails application with Ruby 3.2.2
- Install nginx and supervisor
- Generate self-signed SSL certificates
- Configure nginx as reverse proxy
- Precompile Rails assets

### 5.3 Push Image to ACR

```bash
docker push ${ACR_NAME}.azurecr.io/icms-inspection-app:latest
```

### 5.4 Verify Image in Registry

```bash
az acr repository list --name $ACR_NAME --output table
```

**Expected Output:**
```
Result
---------------------
icms-inspection-app
```

---

## Step 6: Create App Service Plan

Create an App Service Plan for hosting the container:

```bash
az appservice plan create \
  --name ${APP_NAME}-plan \
  --resource-group $RESOURCE_GROUP \
  --is-linux \
  --sku B1 \
  --location $LOCATION
```

---

## Step 7: Create Web App

### 7.1 Get ACR Credentials

```bash
export ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
export ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)
```

### 7.2 Create Web App

```bash
az webapp create \
  --resource-group $RESOURCE_GROUP \
  --plan ${APP_NAME}-plan \
  --name $APP_NAME \
  --deployment-container-image-name ${ACR_NAME}.azurecr.io/icms-inspection-app:latest
```

---

## Step 8: Configure Container Settings

### 8.1 Configure Container Registry

```bash
az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-custom-image-name ${ACR_NAME}.azurecr.io/icms-inspection-app:latest \
  --docker-registry-server-url https://${ACR_NAME}.azurecr.io \
  --docker-registry-server-user $ACR_USERNAME \
  --docker-registry-server-password $ACR_PASSWORD
```

### 8.2 Enable Container Logging

```bash
az webapp log config \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-container-logging filesystem
```

---

## Step 9: Configure Application Settings

### 9.1 Generate Rails Secret Key Base

```bash
export SECRET_KEY_BASE=$(openssl rand -hex 64)
echo "Generated SECRET_KEY_BASE: $SECRET_KEY_BASE"
```

### 9.2 Set Environment Variables

Configure all required environment variables for the Rails application:

```bash
# Set your Azure OpenAI credentials
export AZURE_OPENAI_ENDPOINT="your-endpoint-here"
export AZURE_OPENAI_API_KEY="your-api-key-here"
export AZURE_OPENAI_DEPLOYMENT_NAME="your-deployment-name-here"
export AZURE_OPENAI_API_VERSION="your-api-version-here"

# Configure all app settings
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings \
    RAILS_ENV=production \
    SECRET_KEY_BASE=$SECRET_KEY_BASE \
    DATABASE_URL=$DATABASE_URL \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true \
    WEBSITES_PORT=80 \
    WEBSITES_CONTAINER_START_TIME_LIMIT=600 \
    AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT \
    AZURE_OPENAI_API_KEY=$AZURE_OPENAI_API_KEY \
    AZURE_OPENAI_DEPLOYMENT_NAME=$AZURE_OPENAI_DEPLOYMENT_NAME \
    AZURE_OPENAI_API_VERSION=$AZURE_OPENAI_API_VERSION
```

---

## Step 10: Enable HTTPS Only

```bash
az webapp update \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --https-only true
```

---

## Step 11: Restart and Verify Deployment

### 11.1 Restart Web App

```bash
az webapp restart \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP
```

### 11.2 Get Application URL

```bash
echo "Application URL: https://${APP_NAME}.azurewebsites.net"
```

### 11.3 Check Application Logs

```bash
az webapp log tail \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP
```

---

## Step 12: Run Database Migrations

**Note:** Since SSH is not enabled in our container, we use Azure Container Instances to run migrations.

### 12.1 Register Container Instance Provider (First Time Only)

If you haven't registered this provider yet:

```bash
az provider register --namespace Microsoft.ContainerInstance

# Wait for registration to complete
az provider show --namespace Microsoft.ContainerInstance --query "registrationState" -o tsv
```

### 12.2 Enable plpgsql Extension (Required for Azure PostgreSQL)

```bash
# Using psql (install with: brew install postgresql on macOS)
PGPASSWORD=$DB_ADMIN_PASSWORD psql \
  -h $DB_HOST \
  -U $DB_ADMIN_USER \
  -d $DB_NAME \
  -c "CREATE EXTENSION IF NOT EXISTS plpgsql;"
```

Or use Azure CLI:

```bash
az postgres flexible-server execute \
  --name $DB_SERVER \
  --admin-user $DB_ADMIN_USER \
  --admin-password $DB_ADMIN_PASSWORD \
  --database-name $DB_NAME \
  --querytext "CREATE EXTENSION IF NOT EXISTS plpgsql;"
```

### 12.3 Run Migrations Using Container Instance

```bash
az container create \
  --resource-group $RESOURCE_GROUP \
  --name migration-runner \
  --image ${ACR_NAME}.azurecr.io/icms-inspection-app:latest \
  --registry-login-server ${ACR_NAME}.azurecr.io \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --os-type Linux \
  --environment-variables \
    RAILS_ENV=production \
    SECRET_KEY_BASE=$SECRET_KEY_BASE \
    DATABASE_URL=$DATABASE_URL \
  --command-line "/bin/bash -c 'cd /rails && bundle exec rails db:migrate'" \
  --restart-policy Never \
  --cpu 1 \
  --memory 1
```

### 12.4 Check Migration Logs

```bash
az container logs --resource-group $RESOURCE_GROUP --name migration-runner
```

### 12.5 Verify Migration Status

```bash
az container show \
  --resource-group $RESOURCE_GROUP \
  --name migration-runner \
  --query "containers[0].instanceView.currentState.{State:state, ExitCode:exitCode}" -o table
```

**Expected Output:**
- State: `Terminated`
- ExitCode: `0` (success)

### 12.6 Create Initial Admin and Test Users

The script `lib/tasks/create_admin_user.rb` will create both admin and test users:

```bash
# First, delete the migration container
az container delete --resource-group $RESOURCE_GROUP --name migration-runner --yes

# Wait a moment
sleep 5

# Create admin and test users
az container create \
  --resource-group $RESOURCE_GROUP \
  --name admin-user-creator \
  --image ${ACR_NAME}.azurecr.io/icms-inspection-app:latest \
  --registry-login-server ${ACR_NAME}.azurecr.io \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --os-type Linux \
  --environment-variables \
    RAILS_ENV=production \
    SECRET_KEY_BASE=$SECRET_KEY_BASE \
    DATABASE_URL=$DATABASE_URL \
  --command-line "/bin/bash -c 'cd /rails && bundle exec rails runner lib/tasks/create_admin_user.rb'" \
  --restart-policy Never \
  --cpu 1 \
  --memory 1

# Check logs
az container logs --resource-group $RESOURCE_GROUP --name admin-user-creator

# Clean up
az container delete --resource-group $RESOURCE_GROUP --name admin-user-creator --yes
```

**Created Users:**
- **Admin User:** admin@icms.com / Admin123!
- **Test User:** tester@icms.com / Tester123!

### 12.7 Clean Up Migration Container

```bash
az container delete --resource-group $RESOURCE_GROUP --name migration-runner --yes
```

---

## Continuous Deployment

### Update Application

When you need to deploy updates:

1. **Build new image:**
   ```bash
   docker build -f Dockerfile.combined -t ${ACR_NAME}.azurecr.io/icms-inspection-app:latest .
   ```

2. **Push to registry:**
   ```bash
   docker push ${ACR_NAME}.azurecr.io/icms-inspection-app:latest
   ```

3. **Restart web app:**
   ```bash
   az webapp restart --name $APP_NAME --resource-group $RESOURCE_GROUP
   ```

---

## Quick Reference Commands

```bash
# View all resources
az resource list --resource-group $RESOURCE_GROUP --output table

# View app URL
az webapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv

# View logs
az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP

# SSH into container
az webapp ssh --name $APP_NAME --resource-group $RESOURCE_GROUP

# Check supervisor status (inside container)
supervisorctl status

# Delete everything (CAUTION!)
az group delete --name $RESOURCE_GROUP --yes
```

---

## Cost Estimate

Current configuration uses:
- **App Service Plan**: B1 (~$13/month)
- **PostgreSQL Flexible Server**: Burstable B1ms (~$12/month)
- **Container Registry**: Basic (~$5/month)

**Total estimated cost:** ~$30/month

---

## Troubleshooting

### Container fails to start
- Check logs: `az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP`
- Verify `WEBSITES_PORT=80` is set correctly
- Ensure database connection is working

### Database connection errors
- Verify firewall rules on PostgreSQL server
- Check `DATABASE_URL` format
- Ensure SSL settings match

### nginx not serving requests
- Check supervisor logs for nginx process status
- Verify nginx.conf syntax
- Check port bindings (nginx should listen on 80 and 443)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-28
**Environment:** Azure West US 3