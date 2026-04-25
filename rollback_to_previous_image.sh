#!/bin/bash
# Rollback Script - Returns to Previous Stable Image (geometricsicmsac12apr26)

set -e

# Load environment variables
source .env.deployment

echo "=========================================="
echo "Rolling Back to Previous Stable Image"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

# Display current configuration
print_info "Current environment:"
print_info "  Resource Group: $RESOURCE_GROUP"
print_info "  App Name: $APP_NAME"
print_info "  Rolling back FROM: geometricsicmsac24apr26"
print_info "  Rolling back TO: geometricsicmsac12apr26"
echo ""

# Ask for confirmation
read -p "Are you sure you want to rollback? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]
then
    print_warning "Rollback cancelled by user"
    exit 0
fi

# Step 1: Check current image
echo "Step 1: Checking current image configuration..."
CURRENT_IMAGE=$(az webapp config container show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "imageAndTag" \
  --output tsv 2>/dev/null || echo "unknown")

print_info "Current image: $CURRENT_IMAGE"
echo ""

# Step 2: Configure app to use old image
echo "Step 2: Switching to previous stable image..."
print_info "Setting image to: geometricsicmsac12apr26.azurecr.io/cms-inspection-app:latest"

if az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-custom-image-name geometricsicmsac12apr26.azurecr.io/cms-inspection-app:latest \
  --docker-registry-server-url https://geometricsicmsac12apr26.azurecr.io \
  --output none; then
  print_success "Image configuration updated"
else
  print_error "Failed to update image configuration"
  exit 1
fi
echo ""

# Step 3: Get ACR credentials (if needed)
echo "Step 3: Updating ACR credentials..."
OLD_ACR_USERNAME=$(az acr credential show \
  --name geometricsicmsac12apr26 \
  --query "username" \
  --output tsv 2>/dev/null || echo "")

if [ -n "$OLD_ACR_USERNAME" ]; then
  OLD_ACR_PASSWORD=$(az acr credential show \
    --name geometricsicmsac12apr26 \
    --query "passwords[0].value" \
    --output tsv)

  az webapp config container set \
    --name $APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --docker-registry-server-user $OLD_ACR_USERNAME \
    --docker-registry-server-password $OLD_ACR_PASSWORD \
    --output none

  print_success "ACR credentials updated"
else
  print_warning "Could not retrieve ACR credentials (may use managed identity)"
fi
echo ""

# Step 4: Restart app
echo "Step 4: Restarting application..."
if az webapp restart \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --output none; then
  print_success "App restart initiated"
else
  print_error "Failed to restart app"
  exit 1
fi
echo ""

# Step 5: Wait
echo "Step 5: Waiting for application to start..."
print_info "Waiting 60 seconds for container to pull and start..."
for i in {1..60}; do
  echo -n "."
  sleep 1
done
echo ""
print_success "Wait complete"
echo ""

# Step 6: Check status
echo "Step 6: Checking application status..."
APP_STATE=$(az webapp show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "state" \
  --output tsv)

if [ "$APP_STATE" == "Running" ]; then
  print_success "Application is running"
else
  print_warning "Application state: $APP_STATE"
  print_info "Check logs with: az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
fi
echo ""

# Step 7: Verify image
echo "Step 7: Verifying rollback..."
NEW_IMAGE=$(az webapp config container show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "imageAndTag" \
  --output tsv 2>/dev/null || echo "unknown")

if [[ $NEW_IMAGE == *"geometricsicmsac12apr26"* ]]; then
  print_success "Rollback verified: $NEW_IMAGE"
else
  print_warning "Image verification inconclusive: $NEW_IMAGE"
fi
echo ""

# Get URL
APP_URL="https://${APP_NAME}.azurewebsites.net"

echo "=========================================="
echo "Rollback Complete!"
echo "=========================================="
print_success "Application has been rolled back to the previous stable image"
echo ""
print_info "Application URL: $APP_URL"
echo ""
echo "Next steps:"
echo "1. Open the application in your browser"
echo "2. Verify functionality:"
echo "   - Login works"
echo "   - Projects load correctly"
echo "   - All existing features work"
echo "3. Check application logs:"
echo "   az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
print_warning "Note: The Drill Logs feature will NOT be available after rollback"
echo ""
echo "=========================================="