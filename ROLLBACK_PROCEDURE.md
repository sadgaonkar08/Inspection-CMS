# Rollback Procedure for Drill Logs Deployment

This document provides step-by-step instructions to rollback to the previous stable image if the new deployment encounters issues.

## Quick Rollback Summary

If the new image (geometricsicmsac24apr26) has issues, rollback to the previous stable image (geometricsicmsac12apr26).

---

## Detailed Rollback Steps

### Prerequisites
- Azure CLI installed and logged in
- Access to the Azure subscription
- Necessary permissions on the resource group

### Step 1: Source Environment Variables

```bash
source .env.deployment
```

**Expected Output:**
```
Environment variables loaded
```

### Step 2: Verify Current Image

Check which image is currently running:

```bash
az webapp config container show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[imageAndTag, registryUrl]" \
  --output table
```

**Expected Output:**
```
ImageAndTag                                      RegistryUrl
----------------------------------------------  ------------------------------------------------
geometricsicmsac24apr26.azurecr.io/cms-inspection-app:latest  https://geometricsicmsac24apr26.azurecr.io
```

### Step 3: Configure App to Use Previous (Stable) Image

Update the app service to point to the old, stable registry:

```bash
az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-custom-image-name geometricsicmsac12apr26.azurecr.io/cms-inspection-app:latest \
  --docker-registry-server-url https://geometricsicmsac12apr26.azurecr.io
```

**Expected Output:**
```json
{
  "name": "geometriceng-icms-app",
  "dockerCustomImageName": "geometricsicmsac12apr26.azurecr.io/cms-inspection-app:latest",
  ...
}
```

### Step 4: Update Container Registry Credentials (if needed)

If you need to update the ACR credentials:

```bash
# Get the old ACR credentials
OLD_ACR_USERNAME=$(az acr credential show \
  --name geometricsicmsac12apr26 \
  --query "username" \
  --output tsv)

OLD_ACR_PASSWORD=$(az acr credential show \
  --name geometricsicmsac12apr26 \
  --query "passwords[0].value" \
  --output tsv)

# Update app service with old ACR credentials
az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-registry-server-user $OLD_ACR_USERNAME \
  --docker-registry-server-password $OLD_ACR_PASSWORD
```

### Step 5: Restart the Application

Force the app service to pull and restart with the old image:

```bash
az webapp restart \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP
```

**Expected Output:**
```
App restart initiated successfully
```

### Step 6: Wait for Application to Start

Wait 30-60 seconds for the container to start:

```bash
echo "Waiting for application to start..."
sleep 60
```

### Step 7: Verify Application Status

Check the application state:

```bash
az webapp show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "state" \
  --output tsv
```

**Expected Output:**
```
Running
```

### Step 8: Check Application Logs

Monitor the logs to ensure the old image is working:

```bash
az webapp log tail \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP
```

**What to Look For:**
- No error messages
- Rails server started successfully
- Database connections working
- No migration errors

Press `Ctrl+C` to exit log tailing.

### Step 9: Verify Application in Browser

Open the application URL:

```bash
echo "Application URL: https://${APP_NAME}.azurewebsites.net"
```

**Verification Checklist:**
- [ ] Application loads without errors
- [ ] Can login successfully
- [ ] Can view projects
- [ ] Can access all existing tabs (Bid Items, Lab Tests, Equipment, etc.)
- [ ] No 500 errors in the logs

---

## Complete Rollback Script

For convenience, here's a single script that performs the complete rollback:

```bash
#!/bin/bash
# rollback_to_previous_image.sh

set -e

# Load environment variables
source .env.deployment

echo "=========================================="
echo "Rolling Back to Previous Stable Image"
echo "=========================================="
echo ""

# Configure app to use old image
echo "Step 1: Switching to previous image (geometricsicmsac12apr26)..."
az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-custom-image-name geometricsicmsac12apr26.azurecr.io/cms-inspection-app:latest \
  --docker-registry-server-url https://geometricsicmsac12apr26.azurecr.io

echo "✅ Image configuration updated"
echo ""

# Restart app
echo "Step 2: Restarting application..."
az webapp restart \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP

echo "✅ App restart initiated"
echo ""

# Wait
echo "Step 3: Waiting for application to start (60 seconds)..."
sleep 60
echo "✅ Wait complete"
echo ""

# Check status
echo "Step 4: Checking application status..."
APP_STATE=$(az webapp show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "state" \
  --output tsv)

if [ "$APP_STATE" == "Running" ]; then
  echo "✅ Application is running"
else
  echo "⚠️  Application state: $APP_STATE"
fi
echo ""

# Get URL
APP_URL="https://${APP_NAME}.azurewebsites.net"
echo "=========================================="
echo "Rollback Complete!"
echo "=========================================="
echo "Application URL: $APP_URL"
echo ""
echo "Please verify the application is working correctly."
echo ""
```

Save this to `rollback_to_previous_image.sh` and make it executable:

```bash
chmod +x rollback_to_previous_image.sh
```

---

## Troubleshooting

### Issue: App won't start after rollback

**Solution:**
1. Check the logs: `az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP`
2. Verify the old image exists in the old registry:
   ```bash
   az acr repository show-tags \
     --name geometricsicmsac12apr26 \
     --repository cms-inspection-app \
     --output table
   ```
3. If image is missing, you may need to rebuild from the previous git commit

### Issue: Database migration conflicts

**Solution:**
The old image will have the old database schema. If the new image ran migrations that are incompatible:

1. Connect to the database and check migration status
2. You may need to manually rollback migrations:
   ```bash
   # SSH into the container
   az webapp ssh --name $APP_NAME --resource-group $RESOURCE_GROUP

   # Inside container, rollback the drill_logs migration
   cd /rails
   bundle exec rails db:migrate:down VERSION=20260425000001
   ```

### Issue: Can't access old ACR (geometricsicmsac12apr26)

**Solution:**
1. Verify you have access:
   ```bash
   az acr login --name geometricsicmsac12apr26
   ```
2. If access is denied, contact Azure admin
3. Alternative: Rebuild the old image from git history

---

## Prevention Tips

### Before Deploying New Features

1. **Tag images with versions** instead of just using `latest`:
   ```bash
   docker build -t ${ACR_NAME}.azurecr.io/cms-inspection-app:v1.0.0
   docker build -t ${ACR_NAME}.azurecr.io/cms-inspection-app:latest
   ```

2. **Take a database backup** before deploying:
   ```bash
   az postgres flexible-server backup list \
     --resource-group $RESOURCE_GROUP \
     --server-name $DB_SERVER
   ```

3. **Test in a staging environment** first

4. **Create a git tag** for the deployment:
   ```bash
   git tag -a v1.1.0-drill-logs -m "Drill logs feature deployment"
   git push origin v1.1.0-drill-logs
   ```

---

## Post-Rollback Actions

After successful rollback:

1. **Document the issue** that caused the rollback
2. **Fix the issue** in the code locally
3. **Test thoroughly** before redeploying
4. **Update the deployment date** in .env.deployment when ready to redeploy

---

## Emergency Contacts

If rollback fails and you need assistance:

- Azure Support: [Azure Portal](https://portal.azure.com) → Support → New Support Request
- Check Azure Service Health: https://status.azure.com/

---

**Last Updated:** April 24, 2026
**Document Version:** 1.0