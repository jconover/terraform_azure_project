#!/usr/bin/env bash
set -euo pipefail

# Terraform import helper with before/after plan comparison
# Usage: ./import-helper.sh <resource_address> <resource_id>

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource_address> <resource_id>"
  echo ""
  echo "Example: $0 azurerm_storage_account.main /subscriptions/.../storageAccounts/mysa"
  exit 1
fi

RESOURCE_ADDRESS="$1"
RESOURCE_ID="$2"
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

echo -e "${BLUE}=== Terraform Import Helper ===${RESET}"
echo -e "Resource: ${YELLOW}${RESOURCE_ADDRESS}${RESET}"
echo -e "ID:       ${YELLOW}${RESOURCE_ID}${RESET}"
echo ""

# Pre-import plan
echo -e "${BLUE}Running pre-import plan...${RESET}"
if terraform plan -no-color > "$TMPDIR/pre-plan.txt" 2>&1; then
  echo -e "${GREEN}Pre-import plan captured.${RESET}"
else
  echo -e "${YELLOW}Pre-import plan completed with changes.${RESET}"
fi

# Import
echo ""
echo -e "${BLUE}Importing resource...${RESET}"
if terraform import "$RESOURCE_ADDRESS" "$RESOURCE_ID"; then
  echo -e "${GREEN}Import successful.${RESET}"
else
  echo -e "${RED}Import failed.${RESET}"
  exit 1
fi

# Post-import plan
echo ""
echo -e "${BLUE}Running post-import plan...${RESET}"
if terraform plan -no-color > "$TMPDIR/post-plan.txt" 2>&1; then
  echo -e "${GREEN}Post-import plan: no changes detected. Import is clean.${RESET}"
else
  echo -e "${YELLOW}Post-import plan shows changes. Review below:${RESET}"
  echo ""
  diff --color=auto "$TMPDIR/pre-plan.txt" "$TMPDIR/post-plan.txt" || true
fi

echo ""
echo -e "${GREEN}=== Import Complete ===${RESET}"
echo -e "Verify with: ${BLUE}terraform plan${RESET}"
echo -e "If changes appear, add lifecycle { ignore_changes } as needed."
