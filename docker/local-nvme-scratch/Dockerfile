FROM ubuntu

RUN  apt-get update && apt-get -y install nvme-cli mdadm && apt-get -y clean && apt-get -y autoremove
COPY setup-local-nvme-scratch.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup-local-nvme-scratch.sh

ENTRYPOINT ["setup-local-nvme-scratch.sh"]