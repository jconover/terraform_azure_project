# Prod environment configuration
# Usage: terraform plan -var-file=prod.tfvars

subscription_id = "00000000-0000-0000-0000-000000000000" # Replace with actual production subscription ID
project         = "platform"
environment     = "prod"
location        = "eastus2"
owner           = "platform-team"
cost_center     = "infrastructure"

tags = {
  criticality = "high"
  compliance  = "required"
}
