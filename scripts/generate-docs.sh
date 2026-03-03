#!/usr/bin/env bash
set -euo pipefail

# Generate documentation for all Terraform modules using terraform-docs

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

MODULES_DIR="modules"
PASS=0
FAIL=0

if ! command -v terraform-docs &>/dev/null; then
  echo -e "${RED}Error: terraform-docs is not installed.${RESET}"
  exit 1
fi

echo -e "${BLUE}Generating module documentation...${RESET}"
echo ""

for module_dir in "$MODULES_DIR"/*/; do
  module_name=$(basename "$module_dir")

  if [[ ! -f "${module_dir}main.tf" ]] && [[ ! -f "${module_dir}variables.tf" ]]; then
    continue
  fi

  if terraform-docs markdown table --output-file README.md --output-mode inject "$module_dir" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${RESET} ${module_name}"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${RESET} ${module_name}"
    ((FAIL++))
  fi
done

echo ""
echo -e "${BLUE}Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
