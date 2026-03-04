# Staging environment configuration
# Usage: terraform plan -var-file=staging.tfvars

subscription_id = "00000000-0000-0000-0000-000000000000" # Replace with actual subscription ID
project         = "platform"
environment     = "staging"
location        = "eastus2"
owner           = "platform-team"
cost_center     = "infrastructure"
