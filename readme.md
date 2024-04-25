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

## Install Volcano
These are the steps to install Volcano on the AKS cluster.
```
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/release-1.7/installer/volcano-development.yaml

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

Volcano jobs can be launched with MPI.  A volcano job creates a "master" pod with a hostfile available in `/etc/volcano/mpiworker.host` that can be used when launching `mpirun`.  However, the NVIDIA operator can cause timeouts when launching the job.  The examples in this repo work around this issue by waiting for `sshd` to be running on all the workers before launching the job.  This is done using bash scripting.

## Build the docker images

The docker images embed the NDv5 topology file.  The topology file is used by the NCCL library to optimize communication between GPUs.  This file is located in the [azhpc-images](https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv5-topo.xml) repository.

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

### OLMo
```
cd olmo
az acr login -n $ACR_NAME
docker build -f Dockerfile_main -t $ACR_NAME.azurecr.io/olmo:main .
docker push $ACR_NAME.azurecr.io/olmo:main
```

## Scale the node pool
```
az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name ndv5 --node-count 2 
```

## Helm examples
```
helm install nccl-allreduce-2n ./examples/nccl-allreduce --set image=$ACR_NAME.azurecr.io/nccltest,numNodes=2
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


# Enable NVME on nodes

This uses code from the [AKS NVME SSD Provisioner](https://github.com/ams0/aks-nvme-ssd-provisioner) project.

Build the docker image:

```
cd aks-nvme-ssd-provisioner
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/aks-nvme-ssd-provisioner .
docker push $ACR_NAME.azurecr.io/aks-nvme-ssd-provisioner
```

Deploy the manifests:

```
helm install aks-nvme-ssd-provisioner ./examples/aks-nvme-ssd-provisioner --set image="$ACR_NAME.azurecr.io/aks-ssd-nvme-provisioner"
```

Apply to the node pool:

```
az aks nodepool update -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -n ndv5 --labels aks-local-ssd=true
```

# Running Olmo

```
git clone https://github.com/allenai/OLMo.git
cd OLMo
git checkout c9ceb5c28a438b03ac3a1442138b60a1fe9dd4ae
pip install -e .[all]
export SCRATCH_DIR=/scratch
mkdir /scratch/checkpoints
export WANDB_MODE=offline

torchrun --nproc_per_node=8 scripts/train.py configs/official/OLMo-1B.yaml
```


more notes:
```
pip install --upgrade pip


torchrun --nproc-per-node 8 --nnodes 2 --rdzv-backend c10d --rdzv-id 1234 --rdzv-endpoint olmo-0:29500 scripts/train.py configs/official/OLMo-1B.yaml

torchrun --nproc-per-node 8 --nnodes 2 --rdzv-backend c10d --rdzv-id 1234 --rdzv-endpoint olmo-0.olmo-service:29500 scripts/train.py configs/official/OLMo-1B.yaml --run_name=olmo-service-test
```

Install azcopy
```
mkdir -p $HOME/bin
pushd $HOME/bin
wget -q https://aka.ms/downloadazcopy-v10-linux -O - | tar zxf - --strip-components 1 --wildcards '*/azcopy'
chmod 755 azcopy 
popd
export PATH=$HOME/bin:$PATH
```

Update to local files
```
sed -i 's|https://olmo-data.org|file:///scratch/olmo-data|g' configs/official/OLMo-*
sed -i 's|scratch/olmo-data|inputdata|g' configs/official/OLMo-*
sed -i 's|inputdata|scratch/olmo-data|g' configs/official/OLMo-*

sed -i 's|https://olmo-data.org|file:///inputdata|g' configs/official/OLMo-*

sed -i 's|https://olmo-data.org|${data_root}|g;2i data_root: file:///inputdata' configs/official/OLMo-*
```

Test io perf:
```
python3 scripts/run_dataloader.py configs/official/OLMo-1B.yaml 
```


```
cd /etc && wget https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv5-topo.xml && cd -
TOPO_FILE=/etc/ndv5-topo.xml
export NCCL_IB_PCI_RELAXED_ORDERING=1
export NCCL_SOCKET_IFNAME=eth0
export NCCL_TOPO_FILE=$TOPO_FILE
export NCCL_MIN_NCHANNELS=32
export UCX_IB_PCI_RELAXED_ORDERING=on
export UCX_MEM_EVENTS=n
export UCX_TLS=rc
export UCX_NET_DEVICES=mlx5_0:1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export SHARP_SMX_UCX_INTERFACE=mlx5_0:1
export SHARP_COLL_ENABLE_SAT=1
export SHARP_COLL_LOG_LEVEL=3
export SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1
```

```
export SCRATCH_DIR=/scratch
export WANDB_MODE=offline
export RANK=$JOB_COMPLETION_INDEX
export WORLD_SIZE=2
export MASTER_ADDR=10.244.7.25
export MASTER_PORT=29500
export NCCL_DEBUG=INFO

python scripts/train.py configs/official/OLMo-1B.yaml
```

# Device mesh

https://pytorch.org/tutorials/recipes/distributed_device_mesh.html?highlight=devicemesh


# Results

## NCCL and SHARP set
```
[2024-04-17 09:42:26] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.25
    train/Perplexity=76,631
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=42,133
[2024-04-17 09:42:38] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.73
    train/Perplexity=45,773
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=45,538
    throughput/device/batches_per_second=0.0869
    System/Peak GPU Memory (MB)=43,309
[2024-04-17 09:42:50] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.64
    train/Perplexity=41,914
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=45,368
    throughput/device/batches_per_second=0.0865
[2024-04-17 09:43:01] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=10.95
    train/Perplexity=56,812
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=45,284
    throughput/device/batches_per_second=0.0864
[2024-04-17 09:43:13] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.49
    train/Perplexity=35,955
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=45,261
    throughput/device/batches_per_second=0.0863
[2024-04-17 09:43:24] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.07
    train/Perplexity=23,740
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=45,269
    throughput/device/batches_per_second=0.0863
[2024-04-17 09:43:36] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.703
    train/Perplexity=16,360
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=45,269
    throughput/device/batches_per_second=0.0863
[2024-04-17 09:43:48] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.381
    train/Perplexity=11,861
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=45,267
    throughput/device/batches_per_second=0.0863
[2024-04-17 09:43:59] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.092
    train/Perplexity=8,879
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=45,259
    throughput/device/batches_per_second=0.0863
[2024-04-17 09:44:11] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.331
    train/Perplexity=11,283
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=45,236
    throughput/device/batches_per_second=0.0863
    System/Peak GPU Memory (MB)=43,309
```

## Just NCCL

```
[2024-04-17 09:59:23] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.25
    train/Perplexity=76,631
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=42,133
[2024-04-17 09:59:35] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.73
    train/Perplexity=45,778
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=45,442
    throughput/device/batches_per_second=0.0867
    System/Peak GPU Memory (MB)=43,309
[2024-04-17 09:59:46] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.64
    train/Perplexity=41,912
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=45,217
    throughput/device/batches_per_second=0.0862
[2024-04-17 09:59:58] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=10.95
    train/Perplexity=56,811
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=45,179
    throughput/device/batches_per_second=0.0862
[2024-04-17 10:00:10] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.49
    train/Perplexity=35,956
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=45,151
    throughput/device/batches_per_second=0.0861
[2024-04-17 10:00:21] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.07
    train/Perplexity=23,739
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=45,136
    throughput/device/batches_per_second=0.0861
[2024-04-17 10:00:33] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.702
    train/Perplexity=16,356
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=45,119
    throughput/device/batches_per_second=0.0861
[2024-04-17 10:00:44] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.381
    train/Perplexity=11,856
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=45,095
    throughput/device/batches_per_second=0.0860
[2024-04-17 10:00:56] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.091
    train/Perplexity=8,879
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=45,080
    throughput/device/batches_per_second=0.0860
[2024-04-17 10:01:08] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.330
    train/Perplexity=11,273
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=45,049
    throughput/device/batches_per_second=0.0859
    System/Peak GPU Memory (MB)=43,309
```

## Default setting
```
[2024-04-17 09:47:10] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.25
    train/Perplexity=76,631
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=42,133
[2024-04-17 09:47:21] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.73
    train/Perplexity=45,777
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=45,439
    throughput/device/batches_per_second=0.0867
    System/Peak GPU Memory (MB)=43,309
[2024-04-17 09:47:33] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.64
    train/Perplexity=41,917
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=45,218
    throughput/device/batches_per_second=0.0862
[2024-04-17 09:47:45] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=10.95
    train/Perplexity=56,812
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=45,142
    throughput/device/batches_per_second=0.0861
[2024-04-17 09:47:56] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.49
    train/Perplexity=35,958
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=45,098
    throughput/device/batches_per_second=0.0860
[2024-04-17 09:48:08] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.07
    train/Perplexity=23,738
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=45,083
    throughput/device/batches_per_second=0.0860
[2024-04-17 09:48:20] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.702
    train/Perplexity=16,355
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=45,073
    throughput/device/batches_per_second=0.0860
[2024-04-17 09:48:31] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.380
    train/Perplexity=11,853
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=45,060
    throughput/device/batches_per_second=0.0859
[2024-04-17 09:48:43] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.091
    train/Perplexity=8,878
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=45,049
    throughput/device/batches_per_second=0.0859
[2024-04-17 09:48:55] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.330
    train/Perplexity=11,270
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=45,020
    throughput/device/batches_per_second=0.0859
    System/Peak GPU Memory (MB)=43,309
```

# olmo 0.2.5 on 2 nodes (bad perf)

```
    System/Peak GPU Memory (MB)=9,720
[2024-04-18 14:24:11] INFO     [olmo.train:729, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.31
    train/Perplexity=81,422
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=56,556
[2024-04-18 14:24:46] INFO     [olmo.train:729, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.88
    train/Perplexity=53,153
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=7,456
    throughput/device/batches_per_second=0.0284
    System/Peak GPU Memory (MB)=57,144
[2024-04-18 14:25:22] INFO     [olmo.train:729, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.84
    train/Perplexity=51,070
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=7,414
    throughput/device/batches_per_second=0.0283
[2024-04-18 14:25:57] INFO     [olmo.train:729, rank=0] [step=4/739328]
    train/CrossEntropyLoss=11.17
    train/Perplexity=71,024
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=7,394
    throughput/device/batches_per_second=0.0282
[2024-04-18 14:26:33] INFO     [olmo.train:729, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.71
    train/Perplexity=44,824
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=7,372
    throughput/device/batches_per_second=0.0281
[2024-04-18 14:27:09] INFO     [olmo.train:729, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.19
    train/Perplexity=26,708
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=7,368
    throughput/device/batches_per_second=0.0281
[2024-04-18 14:27:45] INFO     [olmo.train:729, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.773
    train/Perplexity=17,545
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=7,358
    throughput/device/batches_per_second=0.0281
[2024-04-18 14:28:20] INFO     [olmo.train:729, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.568
    train/Perplexity=14,306
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=7,356
    throughput/device/batches_per_second=0.0281
[2024-04-18 14:28:56] INFO     [olmo.train:729, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.337
    train/Perplexity=11,354
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=7,353
    throughput/device/batches_per_second=0.0281
[2024-04-18 14:29:32] INFO     [olmo.train:729, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.467
    train/Perplexity=12,930
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=7,352
    throughput/device/batches_per_second=0.0280
    System/Peak GPU Memory (MB)=57,144
```

# single node 0.2.5

```
[2024-04-18 14:55:30] INFO     [olmo.train:729, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.25
    train/Perplexity=76,631
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=57,148
[2024-04-18 14:55:46] INFO     [olmo.train:729, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.73
    train/Perplexity=45,775
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=33,809
    throughput/device/batches_per_second=0.0645
    System/Peak GPU Memory (MB)=58,325
[2024-04-18 14:56:01] INFO     [olmo.train:729, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.64
    train/Perplexity=41,906
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=33,733
    throughput/device/batches_per_second=0.0643
[2024-04-18 14:56:17] INFO     [olmo.train:729, rank=0] [step=4/739328]
    train/CrossEntropyLoss=10.95
    train/Perplexity=56,806
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=33,699
    throughput/device/batches_per_second=0.0643
[2024-04-18 14:56:33] INFO     [olmo.train:729, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.49
    train/Perplexity=35,957
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=33,695
    throughput/device/batches_per_second=0.0643
[2024-04-18 14:56:48] INFO     [olmo.train:729, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.07
    train/Perplexity=23,733
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=33,679
    throughput/device/batches_per_second=0.0642
[2024-04-18 14:57:04] INFO     [olmo.train:729, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.702
    train/Perplexity=16,344
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=33,671
    throughput/device/batches_per_second=0.0642
[2024-04-18 14:57:19] INFO     [olmo.train:729, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.379
    train/Perplexity=11,841
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=33,665
    throughput/device/batches_per_second=0.0642
[2024-04-18 14:57:35] INFO     [olmo.train:729, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.091
    train/Perplexity=8,877
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=33,659
    throughput/device/batches_per_second=0.0642
[2024-04-18 14:57:51] INFO     [olmo.train:729, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.328
    train/Perplexity=11,248
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=33,643
    throughput/device/batches_per_second=0.0642
    System/Peak GPU Memory (MB)=58,325
```


# 1B model: 2 nodes x 8 GPUs

```
[2024-04-18 18:17:16] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.31
    train/Perplexity=81,424
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=41,540
[2024-04-18 18:17:22] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.88
    train/Perplexity=53,158
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=44,550
    throughput/device/batches_per_second=0.1699
    System/Peak GPU Memory (MB)=42,130
[2024-04-18 18:17:28] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.84
    train/Perplexity=51,068
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=44,376
    throughput/device/batches_per_second=0.1693
[2024-04-18 18:17:34] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=11.17
    train/Perplexity=71,024
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=44,302
    throughput/device/batches_per_second=0.1690
[2024-04-18 18:17:40] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.71
    train/Perplexity=44,824
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=44,266
    throughput/device/batches_per_second=0.1689
[2024-04-18 18:17:46] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.19
    train/Perplexity=26,710
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=44,149
    throughput/device/batches_per_second=0.1684
[2024-04-18 18:17:52] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.773
    train/Perplexity=17,550
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=44,141
    throughput/device/batches_per_second=0.1684
[2024-04-18 18:17:58] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.568
    train/Perplexity=14,300
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=44,130
    throughput/device/batches_per_second=0.1683
[2024-04-18 18:18:04] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.336
    train/Perplexity=11,337
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=44,119
    throughput/device/batches_per_second=0.1683
[2024-04-18 18:18:10] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.465
    train/Perplexity=12,904
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=44,069
    throughput/device/batches_per_second=0.1681
    System/Peak GPU Memory (MB)=42,130
```

# Blobfuse 2x8 with IB

```
[2024-04-23 11:37:04] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.31
    train/Perplexity=81,424
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=41,540
[2024-04-23 11:37:31] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.88
    train/Perplexity=53,158
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=16,222
    throughput/device/batches_per_second=0.0619
    System/Peak GPU Memory (MB)=42,130
[2024-04-23 11:37:58] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.84
    train/Perplexity=51,073
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=12,130
    throughput/device/batches_per_second=0.0463
[2024-04-23 11:38:27] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=11.17
    train/Perplexity=71,028
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=10,841
    throughput/device/batches_per_second=0.0414
[2024-04-23 11:38:59] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.71
    train/Perplexity=44,824
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=10,099
    throughput/device/batches_per_second=0.0385
[2024-04-23 11:39:24] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.19
    train/Perplexity=26,709
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=10,163
    throughput/device/batches_per_second=0.0388
[2024-04-23 11:39:52] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.773
    train/Perplexity=17,547
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=10,029
    throughput/device/batches_per_second=0.0383
[2024-04-23 11:40:20] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.568
    train/Perplexity=14,304
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=9,900
    throughput/device/batches_per_second=0.0378
[2024-04-23 11:40:49] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.337
    train/Perplexity=11,347
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=9,805
    throughput/device/batches_per_second=0.0374
[2024-04-23 11:41:16] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.466
    train/Perplexity=12,918
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=9,789
    throughput/device/batches_per_second=0.0373
    System/Peak GPU Memory (MB)=42,130
```

# OLMo 1B 2x8 after flushing cache from NVME

```
[2024-04-23 14:19:30] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.31
    train/Perplexity=81,424
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=41,540
[2024-04-23 14:19:36] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.88
    train/Perplexity=53,158
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=44,341
    throughput/device/batches_per_second=0.1691
    System/Peak GPU Memory (MB)=42,130
[2024-04-23 14:19:42] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.84
    train/Perplexity=51,073
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=44,159
    throughput/device/batches_per_second=0.1685
[2024-04-23 14:19:48] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=11.17
    train/Perplexity=71,027
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=44,120
    throughput/device/batches_per_second=0.1683
[2024-04-23 14:19:54] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.71
    train/Perplexity=44,825
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=44,096
    throughput/device/batches_per_second=0.1682
[2024-04-23 14:20:00] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.19
    train/Perplexity=26,709
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=44,069
    throughput/device/batches_per_second=0.1681
[2024-04-23 14:20:06] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.773
    train/Perplexity=17,547
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=44,045
    throughput/device/batches_per_second=0.1680
[2024-04-23 14:20:12] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.568
    train/Perplexity=14,300
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=44,030
    throughput/device/batches_per_second=0.1680
[2024-04-23 14:20:18] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.336
    train/Perplexity=11,341
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=44,016
    throughput/device/batches_per_second=0.1679
[2024-04-23 14:20:24] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.466
    train/Perplexity=12,908
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=43,939
    throughput/device/batches_per_second=0.1676
    System/Peak GPU Memory (MB)=42,130
```

# 2x8 IB with blobfuse disk cache
```
[2024-04-24 09:14:25] INFO     [olmo.train:816, rank=0] [step=1/739328]
    train/CrossEntropyLoss=11.31
    train/Perplexity=81,424
    throughput/total_tokens=4,194,304
    System/Peak GPU Memory (MB)=41,540
[2024-04-24 09:14:32] INFO     [olmo.train:816, rank=0] [step=2/739328]
    train/CrossEntropyLoss=10.88
    train/Perplexity=53,160
    throughput/total_tokens=8,388,608
    throughput/device/tokens_per_second=37,586
    throughput/device/batches_per_second=0.1434
    System/Peak GPU Memory (MB)=42,130
[2024-04-24 09:14:39] INFO     [olmo.train:816, rank=0] [step=3/739328]
    train/CrossEntropyLoss=10.84
    train/Perplexity=51,072
    throughput/total_tokens=12,582,912
    throughput/device/tokens_per_second=39,148
    throughput/device/batches_per_second=0.1493
[2024-04-24 09:14:45] INFO     [olmo.train:816, rank=0] [step=4/739328]
    train/CrossEntropyLoss=11.17
    train/Perplexity=71,026
    throughput/total_tokens=16,777,216
    throughput/device/tokens_per_second=39,962
    throughput/device/batches_per_second=0.1524
[2024-04-24 09:14:51] INFO     [olmo.train:816, rank=0] [step=5/739328]
    train/CrossEntropyLoss=10.71
    train/Perplexity=44,825
    throughput/total_tokens=20,971,520
    throughput/device/tokens_per_second=40,526
    throughput/device/batches_per_second=0.1546
[2024-04-24 09:14:58] INFO     [olmo.train:816, rank=0] [step=6/739328]
    train/CrossEntropyLoss=10.19
    train/Perplexity=26,710
    throughput/total_tokens=25,165,824
    throughput/device/tokens_per_second=40,132
    throughput/device/batches_per_second=0.1531
[2024-04-24 09:15:04] INFO     [olmo.train:816, rank=0] [step=7/739328]
    train/CrossEntropyLoss=9.773
    train/Perplexity=17,548
    throughput/total_tokens=29,360,128
    throughput/device/tokens_per_second=40,591
    throughput/device/batches_per_second=0.1548
[2024-04-24 09:15:11] INFO     [olmo.train:816, rank=0] [step=8/739328]
    train/CrossEntropyLoss=9.568
    train/Perplexity=14,305
    throughput/total_tokens=33,554,432
    throughput/device/tokens_per_second=40,154
    throughput/device/batches_per_second=0.1532
[2024-04-24 09:15:18] INFO     [olmo.train:816, rank=0] [step=9/739328]
    train/CrossEntropyLoss=9.337
    train/Perplexity=11,348
    throughput/total_tokens=37,748,736
    throughput/device/tokens_per_second=39,786
    throughput/device/batches_per_second=0.1518
[2024-04-24 09:15:24] INFO     [olmo.train:816, rank=0] [step=10/739328]
    train/CrossEntropyLoss=9.467
    train/Perplexity=12,921
    throughput/total_tokens=41,943,040
    throughput/device/tokens_per_second=39,916
    throughput/device/batches_per_second=0.1523
    System/Peak GPU Memory (MB)=42,130
```


# IB packages

```
apt install -y ibutils infiniband-diags libibverbs-dev librdmacm-dev libibmad-dev opensm ibverbs-utils
```

# Waiting for a job with kubectl
```
kubectl wait pod -l job-name=olmo2 --for=condition=Ready --timeout=600s
```

# Blob fuse CSI driver

```
helm repo add blob-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/blob-csi-driver/master/charts
helm install blob-csi-driver blob-csi-driver/blob-csi-driver --set node.enableBlobfuseProxy=true --namespace kube-system --set node.blobfuseProxy.blobfuse2Version="2.2.1" --version v1.24.1 --wait
```


```
account_name=aibenchdata
container_name=olmo-data

start_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
expiry_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ" --date "next month")

sas_token=$(az storage container generate-sas \
   --account-name $account_name \
   --name $container_name \
   --permissions rwld \
   --start $start_date \
   --expiry $expiry_date \
   -o tsv)

kubectl create secret generic \
    ${account_name}-${container_name}-sas-token \
    --from-literal azurestorageaccountname=${account_name} \
    --from-literal azurestorageaccountkey="${sas_token}" --type=Opaque
```


# Dstat
```
dstat -m -n -N eth0,total -d -D sda,sdb,md0
```

# Drop cache



# Hugging face issue
```
export HF_DATASETS_OFFLINE=1
```