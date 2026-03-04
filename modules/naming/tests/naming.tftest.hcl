# Terraform tests for the naming module
# Uses command = plan since the module is pure locals (no providers needed)

# ==============================================================================
# Test 1: Basic name generation with default values
# ==============================================================================
run "basic_name_generation" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "myproj-dev-eus2"
    error_message = "Base name should be 'myproj-dev-eus2', got '${output.base_name}'"
  }

  assert {
    condition     = output.location_short == "eus2"
    error_message = "Location short should be 'eus2', got '${output.location_short}'"
  }
}

# ==============================================================================
# Test 2: All resource type outputs follow standard naming pattern
# ==============================================================================
run "all_resource_type_outputs" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.resource_group == "myproj-dev-eus2-rg"
    error_message = "Resource group name should be 'myproj-dev-eus2-rg', got '${output.resource_group}'"
  }

  assert {
    condition     = output.virtual_network == "myproj-dev-eus2-vnet"
    error_message = "Virtual network name should be 'myproj-dev-eus2-vnet', got '${output.virtual_network}'"
  }

  assert {
    condition     = output.subnet == "myproj-dev-eus2-snet"
    error_message = "Subnet name should be 'myproj-dev-eus2-snet', got '${output.subnet}'"
  }

  assert {
    condition     = output.network_security_group == "myproj-dev-eus2-nsg"
    error_message = "NSG name should be 'myproj-dev-eus2-nsg', got '${output.network_security_group}'"
  }

  assert {
    condition     = output.public_ip == "myproj-dev-eus2-pip"
    error_message = "Public IP name should be 'myproj-dev-eus2-pip', got '${output.public_ip}'"
  }

  assert {
    condition     = output.private_endpoint == "myproj-dev-eus2-pe"
    error_message = "Private endpoint name should be 'myproj-dev-eus2-pe', got '${output.private_endpoint}'"
  }

  assert {
    condition     = output.aks_cluster == "myproj-dev-eus2-aks"
    error_message = "AKS cluster name should be 'myproj-dev-eus2-aks', got '${output.aks_cluster}'"
  }

  assert {
    condition     = output.log_analytics_workspace == "myproj-dev-eus2-law"
    error_message = "Log analytics name should be 'myproj-dev-eus2-law', got '${output.log_analytics_workspace}'"
  }

  assert {
    condition     = output.managed_identity == "myproj-dev-eus2-id"
    error_message = "Managed identity name should be 'myproj-dev-eus2-id', got '${output.managed_identity}'"
  }

  assert {
    condition     = output.fabric_capacity == "myproj-dev-eus2-fc"
    error_message = "Fabric capacity name should be 'myproj-dev-eus2-fc', got '${output.fabric_capacity}'"
  }
}

# ==============================================================================
# Test 3: Storage account name compliance (no hyphens, max 24 chars, lowercase)
# ==============================================================================
run "storage_account_no_hyphens" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  # Storage name should have no hyphens
  assert {
    condition     = output.storage_account == "myprojdeveus2st"
    error_message = "Storage account name should be 'myprojdeveus2st', got '${output.storage_account}'"
  }

  # Verify no hyphens present
  assert {
    condition     = !can(regex("-", output.storage_account))
    error_message = "Storage account name must not contain hyphens"
  }
}

run "storage_account_max_24_chars" {
  command = plan

  variables {
    project     = "longproj"
    environment = "staging"
    location    = "australiasoutheast"
    unique_seed = "a-very-long-unique-seed-for-testing-purposes"
  }

  # Storage name must be max 24 characters
  assert {
    condition     = length(output.storage_account) <= 24
    error_message = "Storage account name must be at most 24 characters, got ${length(output.storage_account)}"
  }

  # Must be lowercase
  assert {
    condition     = output.storage_account == lower(output.storage_account)
    error_message = "Storage account name must be lowercase"
  }

  # Must not contain hyphens
  assert {
    condition     = !can(regex("-", output.storage_account))
    error_message = "Storage account name must not contain hyphens"
  }
}

run "storage_account_with_unique_seed" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
    unique_seed = "test-seed"
  }

  # With a unique seed, storage name should include a hash suffix
  assert {
    condition     = length(output.storage_account) > length("myprojdeveus2st")
    error_message = "Storage account name with unique_seed should be longer than base name"
  }

  assert {
    condition     = length(output.storage_account) <= 24
    error_message = "Storage account name must be at most 24 characters even with unique_seed"
  }
}

# ==============================================================================
# Test 4: Key vault name compliance (max 24 chars)
# ==============================================================================
run "key_vault_name_standard" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.key_vault == "myproj-dev-eus2-kv"
    error_message = "Key vault name should be 'myproj-dev-eus2-kv', got '${output.key_vault}'"
  }
}

run "key_vault_name_max_24_chars" {
  command = plan

  variables {
    project     = "longproj"
    environment = "staging"
    location    = "australiasoutheast"
    suffix      = "extra"
  }

  assert {
    condition     = length(output.key_vault) <= 24
    error_message = "Key vault name must be at most 24 characters, got ${length(output.key_vault)} chars: '${output.key_vault}'"
  }
}

# ==============================================================================
# Test 5: Different environments (dev, staging, prod)
# ==============================================================================
run "environment_dev" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "myproj-dev-eus2"
    error_message = "Dev environment base name should be 'myproj-dev-eus2', got '${output.base_name}'"
  }
}

run "environment_staging" {
  command = plan

  variables {
    project     = "myproj"
    environment = "staging"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "myproj-staging-eus2"
    error_message = "Staging environment base name should be 'myproj-staging-eus2', got '${output.base_name}'"
  }

  assert {
    condition     = output.resource_group == "myproj-staging-eus2-rg"
    error_message = "Staging resource group should be 'myproj-staging-eus2-rg', got '${output.resource_group}'"
  }
}

run "environment_prod" {
  command = plan

  variables {
    project     = "myproj"
    environment = "prod"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "myproj-prod-eus2"
    error_message = "Prod environment base name should be 'myproj-prod-eus2', got '${output.base_name}'"
  }

  assert {
    condition     = output.resource_group == "myproj-prod-eus2-rg"
    error_message = "Prod resource group should be 'myproj-prod-eus2-rg', got '${output.resource_group}'"
  }
}

# ==============================================================================
# Test 6: Different locations
# ==============================================================================
run "location_eastus2" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.location_short == "eus2"
    error_message = "eastus2 should abbreviate to 'eus2', got '${output.location_short}'"
  }
}

run "location_westus2" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "westus2"
  }

  assert {
    condition     = output.location_short == "wus2"
    error_message = "westus2 should abbreviate to 'wus2', got '${output.location_short}'"
  }

  assert {
    condition     = output.base_name == "myproj-dev-wus2"
    error_message = "Base name with westus2 should be 'myproj-dev-wus2', got '${output.base_name}'"
  }
}

run "location_westeurope" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "westeurope"
  }

  assert {
    condition     = output.location_short == "weu"
    error_message = "westeurope should abbreviate to 'weu', got '${output.location_short}'"
  }
}

run "location_southeastasia" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "southeastasia"
  }

  assert {
    condition     = output.location_short == "sea"
    error_message = "southeastasia should abbreviate to 'sea', got '${output.location_short}'"
  }
}

run "location_swedencentral" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "swedencentral"
  }

  assert {
    condition     = output.location_short == "sec"
    error_message = "swedencentral should abbreviate to 'sec', got '${output.location_short}'"
  }
}

# ==============================================================================
# Test 7: Custom suffix handling
# ==============================================================================
run "suffix_empty_default" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
  }

  # Without suffix, names should not have trailing suffix component
  assert {
    condition     = output.resource_group == "myproj-dev-eus2-rg"
    error_message = "Without suffix, resource group should be 'myproj-dev-eus2-rg', got '${output.resource_group}'"
  }
}

run "suffix_custom_value" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
    suffix      = "001"
  }

  assert {
    condition     = output.resource_group == "myproj-dev-eus2-rg-001"
    error_message = "With suffix '001', resource group should be 'myproj-dev-eus2-rg-001', got '${output.resource_group}'"
  }

  assert {
    condition     = output.virtual_network == "myproj-dev-eus2-vnet-001"
    error_message = "With suffix '001', vnet should be 'myproj-dev-eus2-vnet-001', got '${output.virtual_network}'"
  }

  assert {
    condition     = output.subnet == "myproj-dev-eus2-snet-001"
    error_message = "With suffix '001', subnet should be 'myproj-dev-eus2-snet-001', got '${output.subnet}'"
  }

  assert {
    condition     = output.aks_cluster == "myproj-dev-eus2-aks-001"
    error_message = "With suffix '001', AKS should be 'myproj-dev-eus2-aks-001', got '${output.aks_cluster}'"
  }
}

run "suffix_affects_key_vault" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "eastus2"
    suffix      = "001"
  }

  assert {
    condition     = output.key_vault == "myproj-dev-eus2-kv-001"
    error_message = "Key vault with suffix should be 'myproj-dev-eus2-kv-001', got '${output.key_vault}'"
  }
}

# ==============================================================================
# Test 8: Variable validation
# ==============================================================================

# Project name validation - minimum 2 characters
run "project_min_length" {
  command = plan

  variables {
    project     = "ab"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "ab-dev-eus2"
    error_message = "2-char project name should work, got '${output.base_name}'"
  }
}

# Project name validation - maximum 10 characters
run "project_max_length" {
  command = plan

  variables {
    project     = "abcdefghij"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "abcdefghij-dev-eus2"
    error_message = "10-char project name should work, got '${output.base_name}'"
  }
}

# Project name must start with a letter
run "project_starts_with_letter" {
  command = plan

  variables {
    project     = "myapp"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "myapp-dev-eus2"
    error_message = "Project starting with letter should work, got '${output.base_name}'"
  }
}

# Project name with hyphens
run "project_with_hyphens" {
  command = plan

  variables {
    project     = "my-app"
    environment = "dev"
    location    = "eastus2"
  }

  assert {
    condition     = output.base_name == "my-app-dev-eus2"
    error_message = "Project with hyphens should work, got '${output.base_name}'"
  }
}

# Invalid project - too short (expect plan failure)
run "project_too_short_rejected" {
  command = plan

  variables {
    project     = "a"
    environment = "dev"
    location    = "eastus2"
  }

  expect_failures = [
    var.project,
  ]
}

# Invalid project - too long (expect plan failure)
run "project_too_long_rejected" {
  command = plan

  variables {
    project     = "abcdefghijk"
    environment = "dev"
    location    = "eastus2"
  }

  expect_failures = [
    var.project,
  ]
}

# Invalid project - starts with number (expect plan failure)
run "project_starts_with_number_rejected" {
  command = plan

  variables {
    project     = "1badname"
    environment = "dev"
    location    = "eastus2"
  }

  expect_failures = [
    var.project,
  ]
}

# Invalid project - uppercase (expect plan failure)
run "project_uppercase_rejected" {
  command = plan

  variables {
    project     = "MyApp"
    environment = "dev"
    location    = "eastus2"
  }

  expect_failures = [
    var.project,
  ]
}

# Invalid environment (expect plan failure)
run "invalid_environment_rejected" {
  command = plan

  variables {
    project     = "myproj"
    environment = "test"
    location    = "eastus2"
  }

  expect_failures = [
    var.environment,
  ]
}

# Invalid location (expect plan failure)
run "invalid_location_rejected" {
  command = plan

  variables {
    project     = "myproj"
    environment = "dev"
    location    = "invalidregion"
  }

  expect_failures = [
    var.location,
  ]
}
