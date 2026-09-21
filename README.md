# openedge

Edge virtual appliance with Docker.

`openedge` builds a minimal Ubuntu Server virtual machine with **Docker Engine** pre-installed and ready to run, designed to be deployed as an edge device on any virtualization platform. It produces a QEMU `qcow2` image (KVM/Proxmox/cloud) and a VirtualBox Vagrant box.

The appliance is produced with [Packer](https://www.packer.io/).

## Features

- Automated, unattended install of Ubuntu Server 18.04
- Docker Engine + Compose plugin pre-installed
- Default user has passwordless sudo and direct access to the `docker` group
- Base CLI utilities (git, wget, curl, vim) and NFS client support included
- Slim final image: Ansible and package caches removed, free space zeroed

## Repository layout

| Path | Purpose |
| --- | --- |
| [`distro/`](distro/) | Packer build source for the virtual appliance |
| [`distro/ubuntu1804.json`](distro/ubuntu1804.json) | The Packer template (qemu + VirtualBox builders, provisioners) |
| [`distro/http/preseed.cfg`](distro/http/preseed.cfg) | Unattended Ubuntu install answers |
| [`distro/scripts/`](distro/scripts/) | Shell provisioning steps (Ansible, setup, Docker, cleanup, disk-zeroing) |
| [`distro/ansible/main.yml`](distro/ansible/main.yml) | Ansible playbook for base utilities |
| [`distro/Vagrantfile`](distro/Vagrantfile) | Tests the built VirtualBox box locally |
| [`distro/builds/`](distro/builds/) | Build output (appliance images, not tracked) |

## Quick start

See [`distro/README.md`](distro/README.md) for the full build guide. In short:

```sh
cd distro
packer plugins install github.com/hashicorp/qemu         # one-time
packer build -only qemu ubuntu1804.json
```

The QEMU appliance lands in `distro/builds/qemu/`. On an x86_64 host you can also build the VirtualBox box with `packer build -only virtualbox-iso ubuntu1804.json`; see the distro README.

## Testing

Boot the QEMU image directly, or `vagrant up` the VirtualBox box from `distro/`:

```sh
cd distro
qemu-system-x86_64 -m 1024 -smp 1 \
  -machine q35,accel=tcg \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -drive file=builds/qemu/openedge,format=qcow2,if=virtio \
  -display cocoa
```

Log in as `vagrant` / `vagrant` and check `docker --version`, `docker compose version`, `docker ps`. See the [distro README](distro/README.md) for details and configuration guidance.

> **Apple Silicon note:** the `qemu` builder works on ARM Macs through full TCG emulation, but the build is very slow. The `virtualbox-iso` builder requires an x86_64 host.

## Requirements

- [Packer](https://www.packer.io/downloads)
- [VirtualBox](https://www.virtualbox.org/)
- [Vagrant](https://www.vagrantup.com/downloads) (optional, for testing)

## License

Released under the [MIT license](LICENSE).