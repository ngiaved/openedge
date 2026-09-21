# openedge distro build

This directory contains the [Packer](https://www.packer.io/) source that builds the `openedge` virtual appliance: a minimal **Ubuntu 18.04 Server** virtual machine with **Docker Engine** pre-installed, packaged as a reusable appliance image.

## How the build works

See the top-level [README](../README.md) for the project overview. The build pipeline is:

1. **Automated install** — Ubuntu Server 18.04.3 is installed unattended from the ISO using `http/preseed.cfg`, creating the default `vagrant` user.
2. **Ansible** — `scripts/ansible.sh` installs Ansible in the guest.
3. **Base config** — `scripts/setup.sh` enables passwordless sudo for `vagrant` and disables unattended upgrades.
4. **Docker** — `scripts/docker.sh` installs Docker Engine, the Compose plugin, and adds `vagrant` to the `docker` group.
5. **Utilities** — the Ansible playbook (`ansible/main.yml`) installs base CLI tools and NFS client support.
6. **Cleanup** — `scripts/cleanup.sh` removes Ansible and purges cached packages; `scripts/zero-disk.sh` additionally zeroes free space on VirtualBox builds only.
7. **Package** — each builder produces its artifact under `builds/` (see below).

Two builders are defined in `ubuntu1804.json`, so the appliance can run on almost any hypervisor:

| Builder | Artifact | Notes |
| --- | --- | --- |
| `qemu` | `builds/qemu/openedge` (raw `qcow2`) | Runs on any host, including Apple Silicon via TCG emulation (slow); ideal for KVM/Proxmox/cloud |
| `virtualbox-iso` | `builds/virtualbox-ubuntu1804.box` (Vagrant box) | Requires an x86_64 host, produces VirtualBox image via the `vagrant` post-processor |

## Requirements

On the build host:

- [Packer](https://www.packer.io/downloads)
- [QEMU](https://www.qemu.org/) for the `qemu` builder
- [VirtualBox](https://www.virtualbox.org/) for the `virtualbox-iso` builder
- [Vagrant](https://www.vagrantup.com/downloads) (only needed to test the built box)

The Ubuntu ISO is downloaded automatically from the Ubuntu archive; to use a cached copy instead, place it at `iso/ubuntu-18.04.3-server-amd64.iso`. A checksum is pinned in `ubuntu1804.json`, so the source ISO is always verified.

## Build

Run from this directory (add `-only` to build a subset):

```sh
packer plugins install github.com/hashicorp/virtualbox   # one-time, for VirtualBox builds
packer plugins install github.com/hashicorp/vagrant      # one-time, for VirtualBox builds
packer plugins install github.com/hashicorp/qemu         # one-time, for QEMU builds
packer plugins install github.com/hashicorp/ansible      # one-time (ansible-local provisioner)

# Build everything (both builders run in parallel):
packer build ubuntu1804.json

# Build a single target:
packer build -only qemu ubuntu1804.json
packer build -only virtualbox-iso ubuntu1804.json
```

> **Apple Silicon note:** the `qemu` builder works on ARM Macs through full TCG emulation, but is **very slow** — budget for a long build. The `virtualbox-iso` builder cannot run x86_64 guests on ARM hosts.

## Test the built image

### VirtualBox box (`virtualbox-iso` build)

```sh
vagrant up
```

The included `Vagrantfile` boots the VirtualBox box and verifies that `docker --version` and `docker compose version` are available inside the appliance.

### QEMU image (`qemu` build)

Boot the `qcow2` directly with QEMU:

```sh
qemu-system-x86_64 -m 1024 -smp 1 \
  -machine q35,accel=tcg \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -drive file=builds/qemu/openedge,format=qcow2,if=virtio \
  -display cocoa
```

- `-display cocoa` opens the macOS GUI window; swap for `-nographic` for a serial console.
- On Apple Silicon this runs through full TCG emulation, so expect it to be slow.

Log in as `vagrant` (password `vagrant`) and verify:

```sh
docker --version
docker compose version
docker ps
```

## Configuring the appliance

The image ships as a stock development box; everyday configuration is done at runtime. Common tasks:

- **Change the password** — `passwd vagrant` (or `sudo passwd root`), then SSH in with `ssh vagrant@<host>`.
- **Static IP / networking** — edit `/etc/netplan/*.yaml` and `sudo netplan apply`, or use your hypervisor's port-forwarding/NAT rules.
- **Deploy applications** — run containers as the `vagrant` user (it's in the `docker` group), e.g. `docker run -d -p 8080:80 nginx`; describe multi-container apps with `docker compose`.
- **System packages** — `sudo apt-get update && sudo apt-get install <pkg>`.

For reproducible, fleet-style configuration, layer a provisioning tool (Ansible, cloud-init, or a config-management agent) on top of SSH — the box has Ansible purged from the final image, so install it on the control machine and use a `remote_user: vagrant` playbook.

If you need to change what's baked into the image itself, edit the defaults in `ubuntu1804.json` and `scripts/*.sh`: the device name, hostname, and user come from `netcfg/get_hostname` plus the `preseed.cfg` user spec; the memory/CPU and disk size come from the builder settings (currently 1–2 vCPU, 1–2 GB RAM, 80 GB disk).

## Default credentials

The appliance ships with a standard development-box account:

| Field | Value |
| --- | --- |
| User | `vagrant` |
| Password | `vagrant` |
| Passwordless sudo | Yes |
| Docker access | Yes (via the `docker` group) |

Change these before deploying anywhere untrusted.

> **Note:** Ubuntu 18.04 (Bionic) reached end-of-life on 31 May 2023. For new deployments, prefer a still-supported LTS and update `iso_urls`, the checksum, and the release codename in `ubuntu1804.json` accordingly.