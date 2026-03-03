// storage-account.bicep
// Bicep template for Azure Storage Account with containers, lifecycle policies, and CMK support
// This is the source template being migrated to Terraform (see modules/storage-account/)

@description('The name of the storage account (3-24 chars, lowercase alphanumeric)')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region for the storage account')
param location string = resourceGroup().location

@description('Resource group name')
param resourceGroupName string = resourceGroup().name

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Standard_RAGRS'
])
param skuName string = 'Standard_LRS'

@description('Storage account kind')
@allowed([
  'StorageV2'
  'BlobStorage'
  'BlockBlobStorage'
])
param kind string = 'StorageV2'

@description('Minimum TLS version')
param minimumTlsVersion string = 'TLS1_2'

@description('Enable HTTPS-only traffic')
param supportsHttpsTrafficOnly bool = true

@description('Allow public network access')
param publicNetworkAccess bool = false

@description('Enable shared access key')
param allowSharedKeyAccess bool = false

@description('Blob soft delete retention in days')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionDays int = 30

@description('Container soft delete retention in days')
@minValue(1)
@maxValue(365)
param containerSoftDeleteRetentionDays int = 30

@description('Enable blob versioning')
param enableVersioning bool = true

@description('Virtual network subnet IDs for network rules')
param virtualNetworkSubnetIds array = []

@description('IP rules for network access')
param ipRules array = []

@description('Network rules bypass options')
param networkRulesBypass array = [
  'AzureServices'
  'Logging'
  'Metrics'
]

@description('Container configurations')
param containers array = []

@description('Lifecycle management rules')
param lifecycleRules array = []

@description('Key Vault key ID for CMK encryption (empty to disable)')
@secure()
param cmkKeyVaultKeyId string = ''

@description('User-assigned identity ID for CMK access')
param cmkUserAssignedIdentityId string = ''

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags')
param tags object = {}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  kind: kind
  sku: {
    name: skuName
  }
  identity: !empty(cmkKeyVaultKeyId) ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cmkUserAssignedIdentityId}': {}
    }
  } : null
  properties: {
    minimumTlsVersion: minimumTlsVersion
    supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
    allowBlobPublicAccess: false
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    allowSharedKeyAccess: allowSharedKeyAccess
    encryption: !empty(cmkKeyVaultKeyId) ? {
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyname: last(split(cmkKeyVaultKeyId, '/'))
        keyvaulturi: substring(cmkKeyVaultKeyId, 0, lastIndexOf(cmkKeyVaultKeyId, '/keys/'))
      }
      identity: {
        userAssignedIdentity: cmkUserAssignedIdentityId
      }
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    } : {
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: join(networkRulesBypass, ',')
      ipRules: [for ip in ipRules: { value: ip, action: 'Allow' }]
      virtualNetworkRules: [for subnetId in virtualNetworkSubnetIds: { id: subnetId, action: 'Allow' }]
    }
  }
  tags: tags
}

// Blob Services - soft delete and versioning
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: blobSoftDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: containerSoftDeleteRetentionDays
    }
    isVersioningEnabled: enableVersioning
  }
}

// Containers
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [
  for container in containers: {
    parent: blobServices
    name: container.name
    properties: {
      publicAccess: contains(container, 'accessType') ? container.accessType : 'None'
    }
  }
]

// Lifecycle management policy
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = if (!empty(lifecycleRules)) {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        for rule in lifecycleRules: {
          name: rule.name
          enabled: contains(rule, 'enabled') ? rule.enabled : true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [ 'blockBlob' ]
              prefixMatch: contains(rule, 'prefixMatch') ? rule.prefixMatch : []
            }
            actions: {
              baseBlob: {
                tierToCool: contains(rule, 'tierToCoolAfterDays') ? {
                  daysAfterModificationGreaterThan: rule.tierToCoolAfterDays
                } : null
                tierToArchive: contains(rule, 'tierToArchiveAfterDays') ? {
                  daysAfterModificationGreaterThan: rule.tierToArchiveAfterDays
                } : null
                delete: contains(rule, 'deleteAfterDays') ? {
                  daysAfterModificationGreaterThan: rule.deleteAfterDays
                } : null
              }
            }
          }
        }
      ]
    }
  }
}

// Diagnostic settings
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${name}-diag'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      { category: 'Transaction', enabled: true }
      { category: 'Capacity', enabled: true }
    ]
  }
}

// Outputs
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output primaryFileEndpoint string = storageAccount.properties.primaryEndpoints.file
