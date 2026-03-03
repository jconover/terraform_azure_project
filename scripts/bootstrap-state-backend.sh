#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Terraform state backend in Azure
# Creates: Resource Group, Storage Account (HTTPS/TLS1.2/soft-delete), Container, Lock

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Defaults
PROJECT="platform"
LOCATION="eastus2"
SUBSCRIPTION=""

usage() {
  echo "Usage: $0 [--project NAME] [--location REGION] [--subscription ID]"
  echo ""
  echo "  --project        Project name (default: platform)"
  echo "  --location       Azure region (default: eastus2)"
  echo "  --subscription   Azure subscription ID (default: current)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --subscription) SUBSCRIPTION="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo -e "${RED}Unknown option: $1${RESET}"; usage ;;
  esac
done

# Validate Azure CLI
if ! command -v az &>/dev/null; then
  echo -e "${RED}Error: Azure CLI (az) is not installed.${RESET}"
  exit 1
fi

if ! az account show &>/dev/null; then
  echo -e "${RED}Error: Not logged into Azure. Run 'az login' first.${RESET}"
  exit 1
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi

SUBSCRIPTION=$(az account show --query id -o tsv)
echo -e "${BLUE}Subscription: ${SUBSCRIPTION}${RESET}"

# Generate unique storage account name
HASH=$(echo -n "$SUBSCRIPTION" | sha256sum | cut -c1-6)
RG_NAME="rg-terraform-state"
SA_NAME="stterraform${HASH}"
CONTAINER_NAME="tfstate"

echo -e "${BLUE}Resource Group:   ${RG_NAME}${RESET}"
echo -e "${BLUE}Storage Account:  ${SA_NAME}${RESET}"
echo -e "${BLUE}Container:        ${CONTAINER_NAME}${RESET}"
echo ""

# Create Resource Group
if az group show --name "$RG_NAME" &>/dev/null; then
  echo -e "${YELLOW}Resource group '${RG_NAME}' already exists, skipping.${RESET}"
else
  echo -e "${BLUE}Creating resource group '${RG_NAME}'...${RESET}"
  az group create \
    --name "$RG_NAME" \
    --location "$LOCATION" \
    --tags environment=shared managed_by=bootstrap project="$PROJECT"
  echo -e "${GREEN}Resource group created.${RESET}"
fi

# Create Storage Account
if az storage account show --name "$SA_NAME" --resource-group "$RG_NAME" &>/dev/null; then
  echo -e "${YELLOW}Storage account '${SA_NAME}' already exists, skipping.${RESET}"
else
  echo -e "${BLUE}Creating storage account '${SA_NAME}'...${RESET}"
  az storage account create \
    --name "$SA_NAME" \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --tags environment=shared managed_by=bootstrap project="$PROJECT"
  echo -e "${GREEN}Storage account created.${RESET}"
fi

# Enable soft delete and versioning
echo -e "${BLUE}Configuring blob service properties...${RESET}"
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 30 \
  --enable-versioning true

echo -e "${GREEN}Blob service properties configured.${RESET}"

# Create container
ACCOUNT_KEY=$(az storage account keys list --account-name "$SA_NAME" --resource-group "$RG_NAME" --query '[0].value' -o tsv)

if az storage container show --name "$CONTAINER_NAME" --account-name "$SA_NAME" --account-key "$ACCOUNT_KEY" &>/dev/null; then
  echo -e "${YELLOW}Container '${CONTAINER_NAME}' already exists, skipping.${RESET}"
else
  echo -e "${BLUE}Creating container '${CONTAINER_NAME}'...${RESET}"
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$SA_NAME" \
    --account-key "$ACCOUNT_KEY"
  echo -e "${GREEN}Container created.${RESET}"
fi

# Apply resource lock
LOCK_EXISTS=$(az lock list --resource-group "$RG_NAME" --query "[?name=='terraform-state-lock']" -o tsv)
if [[ -n "$LOCK_EXISTS" ]]; then
  echo -e "${YELLOW}Resource lock already exists, skipping.${RESET}"
else
  echo -e "${BLUE}Applying CanNotDelete lock...${RESET}"
  az lock create \
    --name "terraform-state-lock" \
    --resource-group "$RG_NAME" \
    --lock-type CanNotDelete \
    --notes "Protects Terraform state backend from accidental deletion"
  echo -e "${GREEN}Lock applied.${RESET}"
fi

echo ""
echo -e "${GREEN}=== Bootstrap Complete ===${RESET}"
echo ""
echo "Add this to your backend.tf:"
echo ""
echo 'terraform {'
echo '  backend "azurerm" {'
echo "    resource_group_name  = \"${RG_NAME}\""
echo "    storage_account_name = \"${SA_NAME}\""
echo "    container_name       = \"${CONTAINER_NAME}\""
echo '    key                  = "<environment>.terraform.tfstate"'
echo '    use_oidc             = true'
echo '  }'
echo '}'
