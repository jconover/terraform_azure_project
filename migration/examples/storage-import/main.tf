# ---------------------------------------------------------------------------
# Worked Example: Import an existing Bicep-deployed Storage Account
# ---------------------------------------------------------------------------
# This configuration mirrors the live resource so that `terraform plan` shows
# zero changes after the import.  Adjust variable values to match the output
# of `az storage account show`.
# ---------------------------------------------------------------------------

# --- Import Block (Terraform 1.5+) ----------------------------------------
# Remove this block after the first successful `terraform apply`.
import {
  to = module.migrated_storage.azurerm_storage_account.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"
}

# --- Module Usage ----------------------------------------------------------
module "migrated_storage" {
  source = "../../../modules/storage-account"

  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Match the existing resource's settings exactly.
  # These values come from `az storage account show` output.
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Security settings — match the Bicep deployment
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = false
  shared_access_key_enabled     = false

  # Soft-delete — Bicep defaults to 7 days; our module defaults to 30.
  # Set explicitly to avoid drift.
  blob_soft_delete_retention_days      = 7
  container_soft_delete_retention_days = 7
  versioning_enabled                   = false

  # Network rules — match existing ACLs
  network_rules_default_action = "Deny"
  network_rules_bypass         = ["AzureServices"]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform" # Updated from "bicep" post-migration
  }
}
