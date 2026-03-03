locals {
  # Location abbreviations
  location_short = lookup({
    eastus             = "eus"
    eastus2            = "eus2"
    westus             = "wus"
    westus2            = "wus2"
    westus3            = "wus3"
    centralus          = "cus"
    northcentralus     = "ncus"
    southcentralus     = "scus"
    northeurope        = "neu"
    westeurope         = "weu"
    uksouth            = "uks"
    ukwest             = "ukw"
    southeastasia      = "sea"
    eastasia           = "ea"
    australiaeast      = "aue"
    australiasoutheast = "ause"
    japaneast          = "jpe"
    japanwest          = "jpw"
    koreacentral       = "krc"
    canadacentral      = "cac"
    brazilsouth        = "brs"
    francecentral      = "frc"
    germanywestcentral = "gwc"
    norwayeast         = "noe"
    switzerlandnorth   = "chn"
    swedencentral      = "sec"
  }, var.location, substr(var.location, 0, 4))

  # Resource type abbreviations (Azure CAF aligned)
  resource_abbreviations = {
    resource_group         = "rg"
    virtual_network        = "vnet"
    subnet                 = "snet"
    network_security_group = "nsg"
    public_ip              = "pip"
    private_endpoint       = "pe"
    key_vault              = "kv"
    storage_account        = "st"
    aks_cluster            = "aks"
    log_analytics          = "law"
    managed_identity       = "id"
    fabric_capacity        = "fc"
  }

  # Base name pattern: {project}-{env}-{location_short}
  base_name = "${var.project}-${var.environment}-${local.location_short}"

  # Suffix component (only added when non-empty)
  suffix_part = var.suffix != "" ? "-${var.suffix}" : ""

  # Generate a unique hash from the seed for globally-unique names
  unique_hash = var.unique_seed != "" ? substr(sha256(var.unique_seed), 0, 6) : ""

  # Standard name builder: {base}-{abbreviation}[-{suffix}]
  standard_names = {
    for key, abbrev in local.resource_abbreviations :
    key => "${local.base_name}-${abbrev}${local.suffix_part}"
  }

  # Storage account: no hyphens, max 24 chars, lowercase alphanumeric only
  storage_base = replace("${var.project}${var.environment}${local.location_short}st", "-", "")
  storage_name = lower(substr(
    "${local.storage_base}${local.unique_hash}",
    0,
    min(24, length("${local.storage_base}${local.unique_hash}"))
  ))

  # Key Vault: max 24 chars, alphanumeric and hyphens
  key_vault_name = substr(
    "${local.base_name}-kv${local.suffix_part}",
    0,
    min(24, length("${local.base_name}-kv${local.suffix_part}"))
  )
}
