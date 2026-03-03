# Terraform Azure Infrastructure Platform
# Usage: make <target> [ENV=<environment>] [MODULE=<module-name>]

ENV     ?= dev
MODULE  ?=
ENV_DIR  = environments/$(ENV)

GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
RED    := \033[0;31m
RESET  := \033[0m

.PHONY: help all fmt validate lint test test-module docs init plan apply destroy drift clean bootstrap cost

help: ## Display available targets
	@echo "$(BLUE)Terraform Azure Platform$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(GREEN)%-16s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables: ENV=$(ENV) MODULE=$(MODULE)"

all: fmt lint validate test ## Run fmt, lint, validate, test

fmt: ## Format all Terraform files
	@echo "$(BLUE)==> Formatting...$(RESET)"
	@terraform fmt -recursive
	@echo "$(GREEN)==> Done$(RESET)"

validate: ## Validate Terraform config (ENV=dev)
	@echo "$(BLUE)==> Validating $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform validate
	@echo "$(GREEN)==> Valid$(RESET)"

lint: ## Run tflint with AzureRM rules
	@echo "$(BLUE)==> Linting...$(RESET)"
	@tflint --config=.tflint.hcl --recursive
	@echo "$(GREEN)==> Clean$(RESET)"

test: ## Run all terraform tests
	@echo "$(BLUE)==> Running tests...$(RESET)"
	@terraform test -test-directory=tests
	@echo "$(GREEN)==> Tests passed$(RESET)"

test-module: ## Test a specific module (MODULE=naming)
	@test -n "$(MODULE)" || (echo "$(RED)MODULE required. Usage: make test-module MODULE=naming$(RESET)" && exit 1)
	@echo "$(BLUE)==> Testing modules/$(MODULE)...$(RESET)"
	@cd modules/$(MODULE) && terraform test
	@echo "$(GREEN)==> Module tests passed$(RESET)"

docs: ## Regenerate module READMEs with terraform-docs
	@echo "$(BLUE)==> Generating docs...$(RESET)"
	@find modules -maxdepth 1 -mindepth 1 -type d -exec terraform-docs markdown table --output-file README.md --output-mode inject {} \;
	@echo "$(GREEN)==> Docs updated$(RESET)"

init: ## Initialize Terraform for environment (ENV=dev)
	@echo "$(BLUE)==> Initializing $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform init
	@echo "$(GREEN)==> Initialized$(RESET)"

plan: ## Plan changes for environment (ENV=dev)
	@echo "$(BLUE)==> Planning $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform plan -var-file=$(ENV).tfvars -out=tfplan
	@echo "$(GREEN)==> Plan saved$(RESET)"

apply: ## Apply changes for environment (ENV=dev)
	@echo "$(YELLOW)==> Applying $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform apply tfplan
	@echo "$(GREEN)==> Applied$(RESET)"

destroy: ## Destroy environment resources (ENV=dev)
	@echo "$(RED)==> DESTROYING $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform destroy -var-file=$(ENV).tfvars

drift: ## Check for infrastructure drift (ENV=dev)
	@echo "$(BLUE)==> Checking drift in $(ENV)...$(RESET)"
	@cd $(ENV_DIR) && terraform plan -detailed-exitcode -var-file=$(ENV).tfvars; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then echo "$(GREEN)==> No drift$(RESET)"; \
	elif [ $$rc -eq 2 ]; then echo "$(YELLOW)==> Drift detected!$(RESET)"; exit 2; \
	else echo "$(RED)==> Error$(RESET)"; exit $$rc; fi

clean: ## Remove .terraform dirs and plan files
	@echo "$(BLUE)==> Cleaning...$(RESET)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "tfplan" -o -name "*.tfplan" -o -name ".terraform.lock.hcl" | xargs rm -f 2>/dev/null || true
	@echo "$(GREEN)==> Clean$(RESET)"

bootstrap: ## Bootstrap state backend in Azure
	@bash scripts/bootstrap-state-backend.sh

cost: ## Run Infracost estimate (ENV=dev)
	@echo "$(BLUE)==> Estimating costs for $(ENV)...$(RESET)"
	@infracost breakdown --path=$(ENV_DIR)
