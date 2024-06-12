ARG FROM_IMAGE_NAME=ubuntu

FROM ${FROM_IMAGE_NAME}

RUN apt update && apt install -y \
    git python3 python3-pip vim wget dnsutils \
    infiniband-diags libibverbs-dev librdmacm-dev libibmad-dev opensm ibverbs-utils

RUN pip install --upgrade pip

RUN cd /opt && \
    git clone https://github.com/allenai/OLMo.git && \
    cd OLMo && \
    pip install -e .[all]

RUN cd /opt/OLMo && \
    sed -i 's|https://olmo-data.org|file:///inputdata|g' configs/official/OLMo-*

RUN cd /etc && \
    wget https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv5-topo.xml && \
    wget https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ndv4-topo.xml && \
    wget https://raw.githubusercontent.com/Azure/azhpc-images/master/topology/ncv4-topo.xml