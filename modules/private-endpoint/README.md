<!-- BEGIN_TF_DOCS -->
# Private Endpoint Module

Creates an Azure Private Endpoint with optional Private DNS Zone integration.

## Usage

```hcl
module "private_endpoint" {
  source = "../../modules/private-endpoint"

  name                          = "pe-storage-blob"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  subnet_id                     = azurerm_subnet.endpoints.id
  private_connection_resource_id = azurerm_storage_account.main.id
  subresource_names             = ["blob"]

  private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]

  tags = {
    Environment = "dev"
  }
}
```
<!-- END_TF_DOCS -->
