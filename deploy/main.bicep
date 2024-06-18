targetScope = 'subscription'

param location string
param resourceGroupName string
param vnetConfig object
param username string
@secure()
param publicKey string
param randomString string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: resourceGroup
  params: {
    location: location
    config: vnetConfig
  }
}

module bastion 'modules/bastion.bicep' = {
  name: 'bastion'
  scope: resourceGroup
  params: {
    location: location
    subnetId: network.outputs.subnetIds.AzureBastionSubnet
  }
  dependsOn: [
    network
  ]
}

module loginNode 'modules/login_node.bicep' = {
  name: 'loginNode'
  scope: resourceGroup
  params: {
    location: location
    subnetId: network.outputs.subnetIds.infra
    username: username
    publicKey: publicKey
  }
  dependsOn: [
    network
  ]
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  scope: resourceGroup
  params: {
    aksName: 'aks${randomString}'
    location: location
    username: username
    publicKey: publicKey
    subnetId: network.outputs.subnetIds.aks
  }
  dependsOn: [
    network
  ]
}

module blobDnsZone 'modules/private_dns_zone.bicep' = {
  name: 'blob-private-dns-zone'
  scope: resourceGroup
  params: {
    privateDNSZoneName: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkName: vnetConfig.name
  }
}

module dfsDnsZone 'modules/private_dns_zone.bicep' = {
  name: 'dfs-private-dns-zone'
  scope: resourceGroup
  params: {
    privateDNSZoneName: 'privatelink.dfs.${environment().suffixes.storage}'
    virtualNetworkName: vnetConfig.name
  }
}

module storage 'modules/blob_storage.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    location: location
    storageName: 'test${randomString}'
    subnetId: network.outputs.subnetIds.aks
    containerName: 'test'
    storageSkuName: 'Standard_LRS'
  }
}

module acrDnsZone 'modules/private_dns_zone.bicep' = {
  name: 'acr-private-dns-zone'
  scope: resourceGroup
  params: {
    privateDNSZoneName: 'privatelink${environment().suffixes.acrLoginServer}'
    virtualNetworkName: vnetConfig.name
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  scope: resourceGroup
  params: {
    subnetId: network.outputs.subnetIds.aks
    acrName: 'acr${randomString}'
    location: location
    acrPrivateDNSZoneName: acrDnsZone.outputs.privateDNSZoneName
  }
}
