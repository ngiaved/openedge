#!/bin/bash -eux

# Uninstall Ansible and remove its PPA; it is only needed for the build.
apt -y remove --purge ansible ansible-core || true
apt-add-repository --remove ppa:ansible/ansible || true

# Apt cleanup.
apt autoremove
apt update

# Delete unneeded files.
rm -f /home/vagrant/*.sh

# Ensure all writes are flushed before the machine is shut down.
sync