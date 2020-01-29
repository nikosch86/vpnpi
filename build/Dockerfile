FROM ubuntu:16.04

RUN set -x; export DEBIAN_FRONTEND=noninteractive; apt-get -q update > /dev/null && \
  apt-get -yq install software-properties-common > /dev/null && \
  apt-add-repository --yes --update ppa:ansible/ansible > /dev/null && \
  apt-get -yq install ansible > /dev/null && \
  apt-get -q clean && \
  rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/ansible
RUN cp /etc/ansible/ansible.cfg /tmp/ansible/

VOLUME /etc/ansible
VOLUME /root/.ssh/
VOLUME /ansible

RUN mkdir -p /tmp/ansible/default-scripts/ /tmp/ansible/default-playbooks/
COPY *-ansible.sh /tmp/ansible/default-scripts/
COPY *.yml /tmp/ansible/default-playbooks/

COPY docker-entrypoint.sh /
RUN chmod +x docker-entrypoint.sh
WORKDIR /ansible
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "ansible-playbook", "--version" ]
