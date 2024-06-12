FROM mcr.microsoft.com/aznhc/aznhc-nv:latest

RUN cd /usr/local/bin \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl

COPY ndv5.conf /azure-nhc/conf/aznhc.conf

COPY run-healthcheck.sh /azure-nhc/run-healthcheck.sh
RUN chmod +x /azure-nhc/run-healthcheck.sh
ENTRYPOINT ["/azure-nhc/run-healthcheck.sh"]