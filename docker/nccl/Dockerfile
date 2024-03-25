ARG FROM_IMAGE_NAME=nvcr.io/nvidia/pytorch:23.10-py3

FROM ${FROM_IMAGE_NAME}

RUN apt update && apt install -y \
    build-essential \
    infiniband-diags \
    openssh-server \
    kmod
    
COPY nccl-tests.sh ndv5-topo.xml ./
RUN ./nccl-tests.sh