# openedge

Edge virtual appliance with Docker.

`openedge` builds a minimal Ubuntu Server virtual machine with **Docker Engine** pre-installed and ready to run, designed to be deployed as an edge device on any virtualization platform. It produces a QEMU `qcow2` image (KVM/Proxmox/cloud), a VirtualBox Vagrant box, and an OVA appliance. Two appliance variants are available: **Ubuntu 24.04 LTS** (autoinstall, current LTS) and **Ubuntu 18.04** (preseed, legacy).

The appliance is produced with [Packer](https://www.packer.io/).

## Features

- Automated, unattended install of **Ubuntu 24.04 LTS** (`ubuntu2404.json`, autoinstall) or **Ubuntu 18.04** (`ubuntu1804.json`, preseed)
- Docker Engine + Compose plugin pre-installed
- Optional offline **preconfigure menu** to bake in a compose source (HTTP/S3/GCS), runtime parameters, a **static network (IP/mask/gateway/DNS)**, a **run-on-boot script** and an **edge-login script**
- **Works out of the box**: with zero configuration, on first boot the appliance downloads a default `docker-compose.yml` (the [sample edge stack](distro/sample/)) over HTTP and starts it with `docker compose up -d`
- At boot, the appliance registers/logs in the device (`edge-login.sh`), runs the user boot script (`runmeonboot`) and fetches `docker-compose.yml` from the configured source to start the stack — no remote access required
- Override with a URL, or set the compose **source to `none`** to disable fetching/starting a stack
- Standard names for the shipped artifacts: `docker-compose.yml`, `runmeonboot`, `edge-login.sh`
- A ready-to-deploy [sample edge stack](distro/sample/) with all three artifacts
- Default user has passwordless sudo and direct access to the `docker` group
- Base CLI utilities (git, wget, curl, vim) and NFS client support included
- Slim final image: Ansible and package caches removed, free space zeroed
- Ships as `qcow2`, VirtualBox Vagrant box, and OVA

## Repository layout

| Path | Purpose |
| --- | --- |
| [`distro/`](distro/) | Packer build source for the virtual appliance |
| [`distro/ubuntu2404.json`](distro/ubuntu2404.json) | Packer template for **Ubuntu 24.04 LTS** (autoinstall) |
| [`distro/ubuntu1804.json`](distro/ubuntu1804.json) | Packer template for **Ubuntu 18.04** (preseed, legacy) |
| [`distro/preconfigure/preconfigure.sh`](distro/preconfigure/preconfigure.sh) | Terminal menu that bakes deployment settings into the image |
| [`distro/http/preseed.cfg`](distro/http/preseed.cfg) | Unattended Ubuntu 18.04 install answers |
| [`distro/http/{user-data,meta-data}`](distro/http/) | Ubuntu 24.04 autoinstall answers (cloud-init nocloud seed) |
| [`distro/scripts/`](distro/scripts/) | Shell provisioning steps (Ansible, setup, Docker, edge bootstrap, network, cleanup, disk-zeroing, OVA packaging) |
| [`distro/ansible/main.yml`](distro/ansible/main.yml) | Ansible playbook for base utilities |
| [`distro/sample/`](distro/sample/) | Sample edge stack: `docker-compose.yml`, `runmeonboot`, `edge-login.sh` |
| [`distro/Vagrantfile`](distro/Vagrantfile) | Tests the built VirtualBox box locally |
| [`distro/builds/`](distro/builds/) | Build output (appliance images, not tracked) |

## Quick start

See [`distro/README.md`](distro/README.md) for the full build guide. In short:

```sh
cd distro
packer plugins install github.com/hashicorp/qemu         # one-time
./preconfigure/preconfigure.sh                           # optional: configure the edge stack
packer build -only qemu ubuntu2404.json                  # Ubuntu 24.04 LTS (default)
# packer build -only qemu ubuntu1804.json                # legacy Ubuntu 18.04
```

The 24.04 QEMU appliance lands in `distro/builds/qemu-2404/`, and the 18.04 one in `distro/builds/qemu/`. On an x86_64 host you can also build the VirtualBox box and OVA with `packer build -only virtualbox-iso ubuntu2404.json`; see the distro README.

## Testing

Boot the QEMU image directly, or `vagrant up` the VirtualBox box from `distro/`:

```sh
cd distro
qemu-system-x86_64 -m 1024 -smp 1 \
  -machine q35,accel=tcg \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -drive file=builds/qemu-2404/openedge-2404,format=qcow2,if=virtio \
  -display cocoa
```

Log in as `vagrant` / `vagrant` and check `docker --version`, `docker compose version`, `docker ps`. Sampled: ~1 minute after boot the [sample stack](distro/sample/) is up — `docker logs -f hello-edge` shows the heartbeat. See the [distro README](distro/README.md) for details and configuration guidance.

For the VirtualBox build, `vagrant up` from `distro/` boots the box, or import the generated OVA directly (`VBoxManage import distro/builds/virtualbox-ubuntu2404.ova`).

> **Apple Silicon note:** the `qemu` builder works on ARM Macs through full TCG emulation, but the build is very slow. The `virtualbox-iso` builder requires an x86_64 host.

## Requirements

- [Packer](https://www.packer.io/downloads)
- [VirtualBox](https://www.virtualbox.org/)
- [Vagrant](https://www.vagrantup.com/downloads) (optional, for testing)

## License

Released under the [MIT license](LICENSE).