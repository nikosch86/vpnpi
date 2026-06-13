#!/bin/sh -e
apt-get -qq update
apt-get install -qq -y python3 python3-apt sshpass
touch /root/.ansible_prereqs_installed
