#!/bin/bash -eux

# Install prerequisites for adding the Docker apt repository.
apt-get -y install ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the stable Docker apt repository for this Ubuntu release.
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list >/dev/null

# Install Docker Engine and the compose plugin.
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow the default 'vagrant' user to manage docker without sudo.
usermod -aG docker vagrant