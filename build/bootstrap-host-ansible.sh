#!/bin/sh -e
apt-get -qq update
apt-get install -qq -y python python-apt python-pycurl sshpass
touch /root/.ansible_prereqs_installed
