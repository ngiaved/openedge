#!/bin/bash -eux

# Install Ansible repository.
apt -y update && apt-get -y upgrade
apt -y install software-properties-common
apt-add-repository -y ppa:ansible/ansible
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367

# Install Ansible.
apt -y update
apt -y install ansible