#!/bin/bash -e

if [ ! -f /etc/ansible/ansible.cfg ]; then
  echo "moving default config into place"
  cp /tmp/ansible/ansible.cfg /etc/ansible/ansible.cfg
  touch /etc/ansible/hosts
  mkdir /etc/ansible/roles
fi

if [ ! -d /ansible/scripts/ ]; then
  echo "moving default scripts in place"
  mkdir -p /ansible/scripts/
  cp /tmp/ansible/default-scripts/*.sh /ansible/scripts/
fi

if [ $(ls /ansible/*yml > /dev/null 2>&1; echo $?) -gt 0 ]; then
  echo "moving default playbooks in place"
  cp /tmp/ansible/default-playbooks/*.yml /ansible/
fi

rm -rf /root/.ssh/*
cp -R /tmp/.ssh /root/
chown root:root /root/.ssh -R
chmod 700 /root/.ssh

exec "$@"
