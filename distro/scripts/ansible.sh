#!/bin/bash -eux

# Install Ansible. 18.04 (bionic) uses the ansible PPA; newer releases install
# the distro's ansible-core package (provides ansible-playbook) instead.
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

apt -y update && apt-get -y upgrade

if [ "$CODENAME" = "bionic" ]; then
  apt -y install software-properties-common
  apt-add-repository -y ppa:ansible/ansible
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
  apt -y update
  apt -y install ansible
else
  apt-get -y install ansible-core
fi