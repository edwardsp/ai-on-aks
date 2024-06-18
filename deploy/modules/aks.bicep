param aksName string
param location string
param username string
param publicKey string
param subnetId string 

resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
    }
    autoUpgradeProfile: {
      upgradeChannel: 'none'
    }
    kubernetesVersion: '1.28.5'
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        vmSize: 'Standard_d4s_v5'
        vnetSubnetID: subnetId
        count: 2
        osType: 'Linux'
        mode: 'System'
      }
    ]
    linuxProfile: {
      adminUsername: username
      ssh: {
        publicKeys: [
          {
            keyData: publicKey
          }
        ]
      }
    }
  }
}

output controlPlaneFQDN string = aks.properties.fqdn
