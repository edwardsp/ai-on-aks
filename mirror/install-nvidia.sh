#!/bin/bash

kubectl get namespace nvidia-operator 2>/dev/null || kubectl create namespace nvidia-operator

# Install node feature discovery
helm upgrade -i --wait \
    node-feature-discovery \
    oci://$ACR_NAME.azurecr.io/helm/node-feature-discovery \
    -n nvidia-operator \
    --set-json master.nodeSelector='{"kubernetes.azure.com/mode": "system"}' \
    --set-json worker.nodeSelector='{"kubernetes.azure.com/accelerator": "nvidia"}' \
    --set-json worker.config.sources.pci.deviceClassWhitelist='["02","03","0200","0207"]' \
    --set-json worker.config.sources.pci.deviceLabelFields='["vendor"]'

helm upgrade -i --wait \
  network-operator \
  oci://$ACR_NAME.azurecr.io/helm/network-operator \
  -n nvidia-operator \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set ofedDriver.deploy=true \
  --set secondaryNetwork.deploy=false \
  --set rdmaSharedDevicePlugin.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name":"mlnxnics","linkTypes": ["infiniband"], "vendors":["15b3"]}]'
# Note: use --set ofedDriver.version="<MOFED VERSION>"
#       to install a specific MOFED version


# Install the gpu-operator
helm upgrade -i --wait \
  gpu-operator \
  oci://$ACR_NAME.azurecr.io/helm/gpu-operator \
  -n nvidia-operator \
  --set nfd.enabled=false \
  --set driver.enabled=true \
  --set driver.rdma.enabled=true \
  --set toolkit.enabled=true
