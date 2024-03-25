#!/bin/bash

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    -n|--cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -l|--location)
      LOCATION="$2"
      shift 2
      ;;
    -a|--acr-name)
      ACR_NAME="$2"
      shift 2
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# Install the aks-preview azcli extension
az extension add --name aks-preview

# Check for InfiniBand support
# $ az feature show --name AKSInfinibandSupport --namespace Microsoft.ContainerService --query properties.state --output tsv
# Registered
if [ "$(az feature show --name AKSInfinibandSupport --namespace Microsoft.ContainerService --query properties.state --output tsv)" != "Registered" ]; then
  echo "InfiniBand support is not registered.  Use the following command:"
  echo "    az feature register --name AKSInfinibandSupport --namespace Microsoft.ContainerService"
  exit 1
fi

# Create a resource group
az group create --resource-group $RESOURCE_GROUP --location $LOCATION

# Create an Azure Container Registry
az acr create \
  -g $RESOURCE_GROUP \
  -n $ACR_NAME \
  --sku Basic \
  --admin-enabled

# Create an AKS cluster with InfiniBand support
az aks create \
  -g $RESOURCE_GROUP \
  --node-resource-group ${RESOURCE_GchmodROUP}-nrg \
  -n $CLUSTER_NAME \
  --enable-managed-identity \
  --node-count 2 \
  --generate-ssh-keys \
  -l $LOCATION \
  --node-vm-size Standard_D2s_v3 \
  --nodepool-name system \
  --os-sku Ubuntu \
  --attach-acr $ACR_NAME

# Add an NDv5 node pool
az aks nodepool add \
  -g $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name ndv5 \
  --node-count 1 \
  --node-vm-size Standard_ND96isr_H100_v5 \
  --node-osdisk-size 128 \
  --os-sku Ubuntu \
  --tags SkipGPUDriverInstall=true

# Setup kubectl to connect to the AKS cluster
az aks get-credentials --overwrite-existing --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
