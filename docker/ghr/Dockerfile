FROM mcr.microsoft.com/aznhc/aznhc-nv:latest

RUN cd /usr/local/bin \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl

RUN apt update && apt install -y jq uuid-runtime
COPY sendghr.sh /azure-nhc/sendghr.sh
RUN chmod +x /azure-nhc/sendghr.sh