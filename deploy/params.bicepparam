using './main.bicep'

param location = readEnvironmentVariable('LOCATION', '')
param resourceGroupName = readEnvironmentVariable('RESOURCE_GROUP', '')

param vnetConfig = {
  name: 'vnet'
  ipRange: '10.128.0.0/20'
  subnets: [
    {
      name: 'infra'
      ipRange: '10.128.0.0/25'
      delegations: []
    }
    {
      name: 'AzureBastionSubnet'
      ipRange: '10.128.0.128/25'
      delegations: []
    }
    {
      name: 'aks'
      ipRange: '10.128.4.0/22'
      delegations: []
    }
  ]
}

param username = readEnvironmentVariable('USERNAME', '')
param publicKey = readEnvironmentVariable('PUBLIC_KEY', '')
param randomString = readEnvironmentVariable('RAND', '')
