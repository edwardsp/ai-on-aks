# AI on AKS

This repository contains scripting and resources for running AI workloads on Azure Kubernetes Service (AKS).

## Installation

### Pre-requisites

* Azure Subscription
* A client with the Azure CLI installed
* Docker for building images
* Quota for GPU nodes on Azure (examples use NDv5)
* Linux shell (use WSL for Windows)

### Define Variables

The following are variables will be used in the deployment steps:

```
export RESOURCE_GROUP=
export LOCATION=
export CLUSTER_NAME=
export ACR_NAME=
```

### Deploy Azure Resources

#### Install the aks-preview azcli extension

The aks-preview extension is required to deploy the AKS cluster with GPU nodes by enabling the skip-gpu-driver-install option.

```
az extension add --name aks-preview
```

#### Enable AKS Infiniband support

The feature need to be registered to ensure the AKS cluster is deployed with Infiniband support.  The following command will register the feature:

```
az feature register --name AKSInfinibandSupport --namespace Microsoft.ContainerService
```

Note: check the feature status with the following command to ensure it is reporting `Registered`:

```
az feature show --name AKSInfinibandSupport --namespace Microsoft.ContainerService --query properties.state --output tsv
```

#### Create a resource group

```
az group create --name $RESOURCE_GROUP --location $LOCATION
```

#### Create an Azure Container Registry

```
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Basic \
    --admin-enabled
```

#### Create an AKS cluster

```
az aks create \
  --resource-group $RESOURCE_GROUP \
  --node-resource-group ${RESOURCE_GROUP}-nrg \
  --name $CLUSTER_NAME \
  --enable-managed-identity \
  --node-count 2 \
  --generate-ssh-keys \
  --location $LOCATION \
  --node-vm-size Standard_D2s_v3 \
  --nodepool-name system \
  --os-sku Ubuntu \
  --attach-acr $ACR_NAME
```

#### Add an NDv5 node pool

This will create a node pool using for NDv5 VMs.  The `SkipGPUDriverInstall=true` tag is used to ensure AKS is not managing the GPU drivers.  Instead we will manage this with the NVIDIA GPU operator.

````
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name ndv5 \
  --node-count 1 \
  --node-vm-size Standard_ND96isr_H100_v5 \
  --node-osdisk-size 128 \
  --os-sku Ubuntu \
  --tags SkipGPUDriverInstall=true
````
### Installing tools

#### Install kubectl

Once the AKS cluster is created you will need to install kubectl to interact with the cluster.  The following commands will install kubectl and configure it to use the AKS cluster:

```
az aks install-cli
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
```

#### Helm

Helm is a package manager for Kubernetes that allows you to easily deploy and manage applications on your AKS cluster.  The following commands will get the latest version of Helm and install it locally:

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

#### K9s (optional)

K9s is a terminal-based UI for Kubernetes that allows you to easily navigate and manage your Kubernetes resources.  The following command will download and install K9s:

```
curl -L https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.tar.gz | tar xz -C ~/bin k9s
```

> Note: This will put k9s in $HOME/path. Ensure the directory is present and in your PATH.

### NVIDIA Drivers

The NVIDIA CPU and Network operators are used to manage the GPU drivers and Infiniband drivers on the NDv5 nodes.  In this configuration we will install the Node Feature Discovery separately as it is used by both operators.  The installations will all use Helm.

#### Create a namespace for the NVIDIA operators

```
kubectl create namespace nvidia-operator
```

#### Install Node Feature Discovery

```
helm upgrade -i --wait \
  -n nvidia-operator node-feature-discovery node-feature-discovery \
  --repo https://kubernetes-sigs.github.io/node-feature-discovery/charts \
  --set-json master.nodeSelector='{"kubernetes.azure.com/mode": "system"}' \
  --set-json worker.nodeSelector='{"kubernetes.azure.com/accelerator": "nvidia"}' \
  --set-json worker.config.sources.pci.deviceClassWhitelist='["02","03","0200","0207"]' \
  --set-json worker.config.sources.pci.deviceLabelFields='["vendor"]'
```

#### Install the Network Operator

```
helm upgrade -i --wait \
  -n nvidia-operator network-operator network-operator \
  --repo https://helm.ngc.nvidia.com/nvidia \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set ofedDriver.deploy=true \
  --set secondaryNetwork.deploy=false \
  --set rdmaSharedDevicePlugin.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name":"mlnxnics","linkTypes": ["infiniband"], "vendors":["15b3"]}]'
```

> Note: use `--set ofedDriver.version="<MOFED-VERSION>"` to install a specific MOFED version

#### Install the GPU Operator

```
helm upgrade -i --wait \
  -n nvidia-operator gpu-operator gpu-operator \
  --repo https://helm.ngc.nvidia.com/nvidia \
  --set nfd.enabled=false \
  --set driver.enabled=true \
  --set driver.rdma.enabled=true \
  --set toolkit.enabled=true
```

> Note: use `--set driver.version="<DRIVER-VERSION>"` to install a specific NVIDIA version

### BLOB Fuse CSI driver

The BLOB Fuse driver is used to mount Azure Blob Storage as a file system.  The following commands will install the driver:

```
helm repo add blob-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/blob-csi-driver/master/charts
helm install blob-csi-driver blob-csi-driver/blob-csi-driver --set node.enableBlobfuseProxy=true --namespace kube-system --set node.blobfuseProxy.blobfuse2Version="2.2.1" --version v1.24.1 --wait
```

### Vulcano

The Volcano scheduler is a Kubernetes-native job scheduler designed to handle advanced scheduling needs, particularly for multi-node jobs in high-performance computing (HPC) and AI/ML workloads.

These are the steps to install Volcano on the AKS cluster:

```
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/release-1.7/installer/volcano-development.yaml

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

## Using the AKS Cluster

### Scaling the Node Pool

The cluster has not be set up with auto scaling.  Manually scale the node pool to the desired number of nodes.  

```
az aks nodepool scale --resource-group $RESOURE_GROUP --cluster-name $CLUSTER_NAME --name ndv5 --node-count 2
```

## Examples

| Name                   | Job Type          | Scheduler   | Parallel launch | Storage              |
|------------------------|-------------------|-------------|-----------------|----------------------|
| Metaseq                | LLM Training      | Volcano job | mpirun          | N/A                  |
| JupyterLab             | Application       | Deployment  | N/A             | Local NVME           |
| NCCL Allreduce         | Network benchmark | Volcano job | mpirun          | N/A                  |
| OLMo                   | LLM Training      | Indexed job | torchrun        | Blobfuse, Local NVME |
| Health check           | Health Check      | Indexed job | N/A             | N/A                  |
| Node Labeler           | Debug             | Daemonset   | N/A             | N/A                  |
| Local NVME Provisioner | Storage           | Daemonset   | N/A             | N/A                  |

The images for the examples are available in the `examples` directory.  Each example will give instructions for building and deploying the image.  The examples that require multi-node will embed the topology file into the image.  Currently only the NDv5 nodes are supported without modification.   This file is located in the [azhpc-images](https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv5-topo.xml) repository.

### Metaseq

| Model Size  | Decoder Layers | Decoder Embed Dim | Decoder Attention Heads | Batch Size | Learning Rate      | Model Parallel |
|:-----------:|:--------------:|:-----------------:|:-----------------------:|:----------:|:------------------:|:--------------:|
| 125m        | 12             | 768               | 12                      | 524288     | 0.0006             | 2              |
| 350m        | 24             | 1024              | 16                      | 524288     | 0.0003             | 2              |
| 760m        | 24             | 1536              | 16                      | 524288     | 0.00025            | 2              |
| 1.3b        | 24             | 2048              | 32                      | 1048576    | 0.0002             | 2              |
| 2.7b        | 32             | 2560              | 32                      | 1048576    | 0.00016            | 4              |
| 6.7b        | 32             | 4096              | 32                      | 2097152    | 0.00012            | 2              |
| 13b         | 40             | 5120              | 40                      | 4194304    | 0.0001             | 2              |
| 30b         | 48             | 7168              | 56                      | 4194304    | 0.0001             | 2              |
| 66b         | 64             | 9216              | 72                      | 2097152    | 0.00008            | 8              |
| 175b        | 96             | 12288             | 96                      | 2097152    | 0.00003            | 8              |

> Reference: [Metaseq source](https://github.com/facebookresearch/metaseq/blob/main/metaseq/launcher/opt_job_constants.py)

#### Build the Metaseq Container Image

```
cd metaseq
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/metaseq .
docker push $ACR_NAME.azurecr.io/metaseq
```

#### Launching a Metaseq Job

This will run a single node and 1.3B model:

```
helm install metaseq \
    ./examples/metaseq \
    --set image=$ACR_NAME.azurecr.io/metaseq \
    --set numNodes=1 \
    --set decoderLayers=24 \
    --set decoderEmbedDim=2048 \
    --set decoderAttentionHeads=32 \
    --set batchSize=1048576 \
    --set learningRate=0.0002 \
    --set modelParallel=2
```

#### Running Aim

To collect metrics for Aim set the parameter `useAim=true` in the helm chart.

Log in to the first worker, change to the log directory and start aim:

```
kubectl exec -it metaseq-mpiworker-0 -- /bin/bash
cd /workspace
aim up
```

Forward the port:

```
kubectl port-forward pod/metaseq-mpiworker-0 43800:43800
```

Now view `localhost:43800` in your browser.

#### Running Tensorboard

To collect metrics for tensorboard set the parameter `useTensorboard=true` in the helm chart.  

Log in to the first worker to run tensorboard:

```
kubectl exec -it metaseq-mpiworker-0 -- /bin/bash
tensorboard serve --logdir=/workspace/tensorboard_logs0000 --bind_all --port=6018
```

Forward the port:

```
kubectl port-forward pod/metaseq-mpiworker-0 6018:6018
```

Now view `localhost:6018` in your browser.

### JupyterLab

#### Pre-requisites

This example requires `local-nvme-provisioner` to be installed.


#### Launching JupyterLab

```
JUPTER_PASSWORD=<set-password>
helm install jupyterlab ./examples/jupyterlab --set "fsSize=4,password=$JUPTER_PASSWORD"
```

### NCCL Allreduce

#### Build the NCCL Allreduce Container Image

```
cd nccl-test
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/nccltest .
docker push $ACR_NAME.azurecr.io/nccltest
```

#### Launching the NCCL Allreduce Job

```
helm install nccl-allreduce-2n ./examples/nccl-allreduce --set image=$ACR_NAME.azurecr.io/nccltest,numNodes=2
```

### OLMo

OLMo is set up to use BLOB storage for the training data and it is mounted to the container with blobfuse.  The amount of bandwidth required for the 1B parameter training is only ~5MB/s.  However the files are very large 32TB and the 5MB is randomly accessed.  Blobfuse is set up to run using block cache, where only blocks are requests and not whole files.  The block size is also set to 4KB and prefetching is disabled.  The 1B parameter model generate 10K transactions per second per NDv5.  There is no performance overhead when using BLOBfuse and the performance is the same as running from local NVME storage.

#### Build the OLMo Container Image

```
cd olmo
az acr login -n $ACR_NAME
docker build -f Dockerfile -t $ACR_NAME.azurecr.io/olmo .
docker push $ACR_NAME.azurecr.io/olmo
```

#### Data Preparation

This OLMo example requires the data to be put in BLOB storage.  

> TODO: show how to copy the OLMo datasets to BLOB storage.

Ensure the BLOB Fuse CSI driver is installed and a storage account and container have been created.  Then add a secret with the SAS token for the storage account.  This can be created as follows:

```
STORAGE_ACCOUNT=
CONTAINER_NAME=

start_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
expiry_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ" --date "next month")

sas_token=$(az storage container generate-sas \
   --account-name $STORAGE_ACCOUNT \
   --name $CONTAINER_NAME \
   --permissions rwld \
   --start $start_date \
   --expiry $expiry_date \
   -o tsv)

kubectl create secret generic \
    ${STORAGE_ACCOUNT}-${CONTAINER_NAME}-sas-token \
    --from-literal azurestorageaccountname=${STORAGE_ACCOUNT} \
    --from-literal azurestorageaccountkey="${sas_token}" --type=Opaque
```

#### Launching the OLMo Job

The storage account and container need to be passed in as values to the helm chart.

```
STORAGE_ACCOUNT=
CONTAINER_NAME=
helm install olmo ./examples/olmojob --set image=h100acr.azurecr.io/olmo,numNodes=1,storageAccount=$STORAGE_ACCOUNT,containerName=$CONTAINER_NAME
```

#### OLMo 1B Training Performance

This was run on 1, 2 and 4 nodes.


### Health Checks

This runs the health checks on the nodes.  This is using the [AzureHPC health checks](https://github.com/Azure/azurehpc-health-checks/tree/main).  A container is [available](https://mcr.microsoft.com/en-us/product/aznhc/aznhc-nv/tags) in the Microsoft Artefact Registry.  The helm chart to run the tests in the repo uses that container although the test config is created to use the device naming for AKS.

Run the tests as follows:

```
helm install health-check ./examples/health-check --set numNodes=1
```

### Health Checks 2

Build the docker image:

```
cd docker/aksnhc
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/aksnhc .
docker push $ACR_NAME.azurecr.io/aksnhc
```



### Node Labeler

This daemonset has been created to identify the node in AKS when reporting any issues. Information is attached to nodes using labels.

Azure has key-value pair files to share information between the host and the guest on Hyper-V. The /var/lib/hyperv/.kvp_pool_3 is read and all the information is added to the node with the hyperv/ prefix.

#### Install the Node Labeler

```
helm install node-labeler ./examples/node-labeler
```

#### Check the Node Labels

Once installed, the hyperv information can be seen as follows:

```
$ kubectl get node <INSERT-NODE-NAME> --show-labels | tr ',' '\n' |grep hyperv
hyperv/HostName=XXX000000000000
hyperv/HostingSystemEditionId=168
hyperv/HostingSystemNestedLevel=0
hyperv/HostingSystemOsMajor=10
hyperv/HostingSystemOsMinor=0
hyperv/HostingSystemProcessorArchitecture=9
hyperv/HostingSystemProcessorIdleStateMax=0
hyperv/HostingSystemProcessorThrottleMax=100
hyperv/HostingSystemProcessorThrottleMin=100
hyperv/HostingSystemSpMajor=0
hyperv/HostingSystemSpMinor=0
hyperv/PhysicalHostName=XXX000000000000
hyperv/PhysicalHostNameFullyQualified=XXX000000000000
hyperv/VirtualMachineDynamicMemoryBalancingEnabled=0
hyperv/VirtualMachineId=DC44D3EB-FA17-4AAB-AE16-E5C5352CB236
hyperv/VirtualMachineName=dfc3f25e-632a-4fb6-8ec8-faece24dcc10
```

### Local NVME Scratch

The NDv5 have 8 NVME drives.  This creates a RAID 0 of the NVME drives on the host.  This needs to be passed through with `hostPath` to the containers.

> Note: originally there was a version based on [local persistent volumes](https://github.com/Azure/kubernetes-volume-drivers/tree/master/local) with the addition of creating a RAID containing all of the NVME devices on a VM.  The issue was creating a separate PVC for each node in a job.

#### Build the Local NVME Scratch Image

This is required to add packages to create a RAID.

```
cd docker/local-nvme-scratch
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/local-nvme-scratch .
docker push $ACR_NAME.azurecr.io/local-nvme-scratch
```

#### Install the Local NVME Provisioner

```
helm install local-nvme-scratch ./examples/local-nvme-scratch --set image="$ACR_NAME.azurecr.io/local-nvme-scratch"
```

#### Apply to the node pool

```
az aks nodepool update -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -n ndv5 --labels local-nvme-scratch=true
```

## Troubleshooting

### Examine a Host

#### Get the node name

Use the following command to find the node name:

```
kubectl get nodes
```

#### Connect to the node

Use the following to connect to the node (setting the $NODE_NAME to the node name):

```
kubectl debug node/$NODE_NAME -it --image=mcr.microsoft.com/cbl-mariner/busybox:2.0
chroot /host
```

Remember to clean up afterwards:
    
```
kubectl delete pod <node-debugger-pod-name>
```

## Notes

### Install azcopy
```
mkdir -p $HOME/bin
pushd $HOME/bin
wget -q https://aka.ms/downloadazcopy-v10-linux -O - | tar zxf - --strip-components 1 --wildcards '*/azcopy'
chmod 755 azcopy 
popd
export PATH=$HOME/bin:$PATH
```


