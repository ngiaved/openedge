#!/bin/bash -eux

# Add the default 'vagrant' user to sudoers with passwordless access.
echo "vagrant        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers

# Disable daily unattended apt upgrades so they don't interrupt the build.
echo 'APT::Periodic::Enable "0";' >> /etc/apt/apt.conf.d/10periodic