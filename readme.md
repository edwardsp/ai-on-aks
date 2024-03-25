# AI on AKS

This document describes how to deploy an AKS cluster with an ACR and run some AI workloads on it.

## Environment variables used throughout this document

Set the following values
```
export RESOURCE_GROUP=
export LOCATION=
export CLUSTER_NAME=
export ACR_NAME=
```

## Deploy the AKS cluster and ACR
```
./deploy.sh --resource-group $RESOURCE_GROUP --location $LOCATION --cluster-name $CLUSTER_NAME --acr-name $ACR_NAME
./nvinstall.sh
```

## Build the docker images

### NCCL test
```
cd nccl-test
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/nccltest .
docker push $ACR_NAME.azurecr.io/nccltest
```

### Metaseq
```
cd metaseq
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/metaseq .
docker push $ACR_NAME.azurecr.io/metaseq
```

## Scale the node pool
```
az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name ndv5 --node-count 2 
```


## Topo file
```
wget https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv5-topo.xml
```

## Install Volcano
```
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/release-1.7/installer/volcano-development.yaml

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

## Helm examples
```
helm install nccl-allreduce-2n ./examples/nccl-allreduce --set image=$ACR_NAME.azurecr.io/nccl-test,numNodes=2
#JUPTER_PASSWORD=<set-password>
helm install jupyterlab ./examples/jupyterlab --set "fsSize=4,password=$JUPTER_PASSWORD"

helm install metaseq \
    ./examples/metaseq \
    --set image=$ACR_NAME.azurecr.io/metaseq \
    --set numNodes=2 \
    --set decoderLayers=40 \
    --set decoderEmbedDim=5120 \
    --set decoderAttentionHeads=40 \
    --set batchSize=4194304 \
    --set learningRate=0.0001 \
    --set modelParallel=2 \
    --set useAim=true
```

Log in to the first worker to run tensorboard:
```
kubectl exec -it metaseq-mpiworker-0 -- /bin/bash
tensorboard serve --logdir=/workspace/tensorboard_logs0000 --bind_all --port=6018
```

Forward the port:
```
kubectl port-forward pod/metaseq-mpiworker-0 6018:6018
```

| Model Size  | Decoder Layers | Decoder Embed Dim | Decoder Attention Heads | Batch Size | Leading Rate       | Model Parallel |
|-------------|----------------|-------------------|-------------------------|------------|--------------------|----------------|
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


## Notes

### Examine host

```
kubectl debug node/$NODE_NAME -it --image=mcr.microsoft.com/cbl-mariner/busybox:2.0
chroot /host
```


### Metaseq parameters 

Reference: [Metaseq source](https://github.com/facebookresearch/metaseq/blob/main/metaseq/launcher/opt_job_constants.py)


| Model  | n_layers | emb_size | n_heads | d_head | batch_size | lr       | model_parallel |
|--------|----------|----------|---------|--------|------------|----------|----------------|
| 8m_mp1 | 4        | 128      | 2       | 64     | 131072     | 0.001    | 1              |
| 8m     | 4        | 128      | 2       | 64     | 131072     | 0.001    | 2              |
| 125m   | 12       | 768      | 12      | 64     | 524288     | 0.0006   | 2              |
| 350m   | 24       | 1024     | 16      | 64     | 524288     | 0.0003   | 2              |
| 760m   | 24       | 1536     | 16      | 96     | 524288     | 0.00025  | 2              |
| 1.3b   | 24       | 2048     | 32      | 64     | 1048576    | 0.0002   | 2              |
| 2.7b   | 32       | 2560     | 32      | 80     | 1048576    | 0.00016  | 4              |
| 6.7b   | 32       | 4096     | 32      | 128    | 2097152    | 0.00012  | 2              |
| 13b    | 40       | 5120     | 40      | 128    | 4194304    | 0.0001   | 2              |
| 30b    | 48       | 7168     | 56      | 128    | 4194304    | 0.0001   | 2              |
| 66b    | 64       | 9216     | 72      | 128    | 2097152    | 0.00008  | 8              |
| 175b   | 96       | 12288    | 96      | 128    | 2097152    | 0.00003  | 8              |