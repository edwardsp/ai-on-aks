param location string
param storageName string
param subnetId string
param containerName string
param storageSkuName string

var storageNameCleaned = replace(storageName, '-', '')

var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var dfsPrivateDnsZoneName = 'privatelink.dfs.${environment().suffixes.storage}'

var storagePleBlobName = '${storageNameCleaned}-blob-pe'
var storagePleDfsName = '${storageNameCleaned}-dfs-pe'


resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: blobPrivateDnsZoneName
}

resource dfsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: dfsPrivateDnsZoneName
}

resource storage 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageNameCleaned
  location: location
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    isHnsEnabled: true
    isNfsV3Enabled: false
    largeFileSharesState: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
  }
}

resource storagePrivateEndpointBlob 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: storagePleBlobName
  location: location
  properties: {
    privateLinkServiceConnections: [
      { 
        name: storagePleBlobName
        properties: {
          groupIds: [
            'blob'
          ]
          privateLinkServiceId: storage.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}


resource privateEndpointDnsBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  name: '${storagePrivateEndpointBlob.name}/blob-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: blobPrivateDnsZoneName
        properties:{
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}


resource storagePrivateEndpointDfs 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: storagePleDfsName
  location: location
  properties: {
    privateLinkServiceConnections: [
      { 
        name: storagePleDfsName
        properties: {
          groupIds: [
            'dfs'
          ]
          privateLinkServiceId: storage.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}


resource privateEndpointDnsDFS 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  name: '${storagePrivateEndpointDfs.name}/dfs-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: dfsPrivateDnsZoneName
        properties:{
          privateDnsZoneId: dfsPrivateDnsZone.id
        }
      }
    ]
  }
}


resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: storageNameCleaned
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-06-01' existing = {
  name: '${storageAccount.name}/default'
}

// Create containers if specified
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  parent: blobService
  dependsOn: [storage]
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {}
  }
}
