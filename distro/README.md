# openedge distro build

This directory contains the [Packer](https://www.packer.io/) source that builds the `openedge` virtual appliance: a minimal **Ubuntu Server** virtual machine with **Docker Engine** pre-installed, packaged as a reusable appliance image. Two templates are provided:

| Template | OS | Installed with | Status |
| --- | --- | --- | --- |
| `ubuntu2404.json` | Ubuntu **24.04 LTS** (Noble) | Subiquity **autoinstall** (`http/user-data` + `meta-data`) | Recommended |
| `ubuntu1804.json` | Ubuntu **18.04** (Bionic) | Debian-installer **preseed** (`http/preseed.cfg`) | Legacy (EOL since May 2023) |

## How the build works

See the top-level [README](../README.md) for the project overview. The build pipeline is:

1. **Preconfigure** (optional) — `preconfigure/preconfigure.sh` is a terminal menu that records where the edge `docker-compose.yml` lives and how to run it. It writes a Packer variable file consumed by either template.
2. **Automated install** — Ubuntu is installed unattended from the ISO: 24.04 via the cloud-init nocloud seed in `http/` (`user-data` + `meta-data`, kernel args `autoinstall ds=nocloud-net;s=http://...`), 18.04 via `http/preseed.cfg`. Both create the default `vagrant` user.
3. **Ansible** — `scripts/ansible.sh` installs Ansible in the guest.
4. **Base config** — `scripts/setup.sh` enables passwordless sudo for `vagrant` and disables unattended upgrades.
5. **Docker** — `scripts/docker.sh` installs Docker Engine, the Compose plugin, and adds `vagrant` to the `docker` group.
6. **Utilities** — the Ansible playbook (`ansible/main.yml`) installs base CLI tools and NFS client support.
7. **Edge bootstrap** — `scripts/edge-bootstrap.sh` bakes the preconfigured compose source, environment and credentials into `/opt/openedge`; if static networking was chosen it writes `/etc/netplan/50-openedge.yaml` and an early apply unit; and it enables the boot service that runs the edge-login script, the user run-on-boot script, and fetches/starts the stack. The service is **enabled by default**: with zero configuration the image downloads the [sample stack](sample/) at first boot and starts it with `docker compose up -d`.
8. **Cleanup** — `scripts/cleanup.sh` removes Ansible and purges cached packages; `scripts/zero-disk.sh` additionally zeroes free space on VirtualBox builds only.
9. **Package** — each builder produces its artifacts under `builds/` (see below).

Two builders are defined in each template, so the appliance can run on almost any hypervisor:

| Template | Builder | Artifact |
| --- | --- | --- |
| `ubuntu2404.json` | `qemu` | `builds/qemu-2404/openedge-2404` (raw `qcow2`) |
| `ubuntu2404.json` | `virtualbox-iso` | `builds/virtualbox-ubuntu2404.box` + `builds/virtualbox-ubuntu2404.ova` |
| `ubuntu1804.json` | `qemu` | `builds/qemu/openedge` (raw `qcow2`) |
| `ubuntu1804.json` | `virtualbox-iso` | `builds/virtualbox-ubuntu1804.box` + `builds/virtualbox-ubuntu1804.ova` |

The `qemu` builder runs on any host, including Apple Silicon via TCG emulation (slow); the `virtualbox-iso` builder requires an x86_64 host and produces the VirtualBox image via the `vagrant` post-processor, then repackages it as OVA.

## Requirements

On the build host:

- [Packer](https://www.packer.io/downloads)
- [QEMU](https://www.qemu.org/) for the `qemu` builder
- [VirtualBox](https://www.virtualbox.org/) for the `virtualbox-iso` builder
- [Vagrant](https://www.vagrantup.com/downloads) (only needed to test the built box)

The Ubuntu ISO is downloaded automatically from the Ubuntu archive; to use cached copies instead, place them at `iso/ubuntu-24.04.5-live-server-amd64.iso` (24.04) and/or `iso/ubuntu-18.04.3-server-amd64.iso` (18.04). A checksum is pinned in each template, so the source ISO is always verified.

## Preconfigure the image

Baking deployment settings into the image is **optional** — with no
configuration at all the appliance still works out of the box: at first boot it
downloads the [sample `docker-compose.yml`](sample/) over HTTP and runs
`docker compose up -d`. Use the menu to point it at your own stack or to disable
fetching. The terminal menu runs fully offline and writes
`openedge.auto.pkrvars.json`, which Packer loads automatically:

```sh
cd distro
./preconfigure/preconfigure.sh
packer build ubuntu2404.json      # picks up openedge.auto.pkrvars.json
```

The menu configures:

| Setting | Purpose |
| --- | --- |
| Compose source | `http` (default, points at the sample stack), `s3`, `gcs`, or `none` (disabled) |
| Compose location | URL, or bucket + object key (plus optional S3 region) |
| Environment variables | `KEY=VALUE` lines written to `/opt/openedge/.env` and interpolated by Compose |
| Project & services | Optional Compose project name and a space-separated service filter |
| Fetch retries | How many times to retry the fetch and how many seconds to wait between attempts |
| Credentials | Optional static S3 keys or a minified GCS service-account JSON (blank uses the instance/IAM/ADC default) |
| Network | `dhcp` (default) or `static` with **IP address, netmask, gateway and DNS servers** |
| Run-on-boot script | URL of the user script fetched and executed on every boot (saved as `/opt/openedge/runmeonboot`) |
| Edge login script | URL of the device registration/login script run at boot (saved as `/opt/openedge/edge-login.sh`) |

At boot the image runs `openedge-bootstrap.service`, which waits for Docker and
the network, then runs — in order — the edge-login script, the run-on-boot
script and finally fetches `docker-compose.yml` from the configured source
(retrying on failure) and runs `docker compose up -d`. Each artifact keeps a
**standard name**: `edge-login.sh`, `runmeonboot` and `docker-compose.yml`, all
under `/opt/openedge`. **No SSH or other remote access is required at runtime**
— the appliance is self-contained. Credentials and the configuration live in
`/opt/openedge` (mode `0600`).

By default the source is `http` and the URL points at the
[`sample/`](sample/) `docker-compose.yml` in this repository, so the boot
service downloads it and starts the workload with **no configuration needed**.
To disable fetching/starting a stack entirely, set the compose source to `none`.

To inspect or script the configuration without the menu:

```sh
./preconfigure/preconfigure.sh --set source=s3 --set bucket=my-bucket \
  --set object=stacks/edge/docker-compose.yml --dump
```

`--set` accepts `source`, `url`, `bucket`, `object`, `project`, `services`,
`retries`, `delay`, `region`, `env`, `credentials`, `net_mode`, `net_address`,
`net_netmask`, `net_gateway`, `net_dns`, `boot_script_url` and `login_url`.
Without `--dump` it saves the settings; `--save` writes them explicitly.

> The image only installs the fetch tool it needs: `curl` for `http`, AWS CLI for
> `s3`, and the Google Cloud SDK (`gsutil`) for `gcs`.

## Build

Run from this directory (add `-only` to build a subset):

```sh
packer plugins install github.com/hashicorp/virtualbox   # one-time, for VirtualBox builds
packer plugins install github.com/hashicorp/vagrant      # one-time, for VirtualBox builds
packer plugins install github.com/hashicorp/qemu         # one-time, for QEMU builds
packer plugins install github.com/hashicorp/ansible      # one-time (ansible-local provisioner)

# Ubuntu 24.04 LTS (recommended):
packer build ubuntu2404.json
packer build -only qemu ubuntu2404.json
packer build -only virtualbox-iso ubuntu2404.json

# Legacy Ubuntu 18.04:
packer build ubuntu1804.json
```

> **Apple Silicon note:** the `qemu` builder works on ARM Macs through full TCG emulation, but is **very slow** — budget for a long build. The `virtualbox-iso` builder cannot run x86_64 guests on ARM hosts.

## Test the built image

### VirtualBox box (`virtualbox-iso` build)

```sh
vagrant up
```

The included `Vagrantfile` boots the VirtualBox box and verifies that `docker --version` and `docker compose version` are available inside the appliance.

### OVA (`virtualbox-iso` build)

The OVA is produced automatically alongside the box (`builds/virtualbox-ubuntu2404.ova` for 24.04, `builds/virtualbox-ubuntu1804.ova` for 18.04). Import it into VirtualBox (File ▸ Import Appliance, or double-click it, or `VBoxManage import builds/virtualbox-ubuntu2404.ova`), start the machine, and
log in as `vagrant` / `vagrant`. The OVA embeds the same VirtualBox image, so it
behaves identically to `vagrant up`.

### QEMU image (`qemu` build)

Boot the `qcow2` directly with QEMU:

```sh
qemu-system-x86_64 -m 1024 -smp 1 \
  -machine q35,accel=tcg \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -drive file=builds/qemu-2404/openedge-2404,format=qcow2,if=virtio \
  -display cocoa
```

(For the 18.04 build, point `-drive` at `builds/qemu/openedge`.)

- `-display cocoa` opens the macOS GUI window; swap for `-nographic` for a serial console.
- On Apple Silicon this runs through full TCG emulation, so expect it to be slow.

Log in as `vagrant` (password `vagrant`) and verify:

```sh
docker --version
docker compose version
docker ps
systemctl status openedge-bootstrap
```

## Configuring the appliance

If you ran the preconfigure menu, the edge stack is already configured: the
appliance fetches and starts it automatically at boot. The relevant files are:

| Path | Purpose |
| --- | --- |
| `/opt/openedge/bootstrap.conf` | Compose source, network, boot/login script and runtime settings |
| `/opt/openedge/.env` | Container environment overrides |
| `/opt/openedge/cloud-creds.conf` | Optional S3/GCS credentials (mode `0600`) |
| `/opt/openedge/openedge-bootstrap.sh` | Boot script: edge-login, runmeonboot, compose fetch/up |
| `/opt/openedge/edge-login.sh` | Device registration/login script (fetched at boot) |
| `/opt/openedge/runmeonboot` | User run-on-boot script (fetched at boot) |
| `/opt/openedge/docker-compose.yml` | The bot/workload stack (fetched at boot) |
| `/opt/openedge/configure-network.sh` | Applies the static netplan early at boot (static mode only) |
| `/etc/netplan/50-openedge.yaml` | Static network config baked at build time (static mode only) |

Re-run the bootstrap after changing settings (this refetches the compose file):

```sh
sudo systemctl restart openedge-bootstrap
sudo journalctl -u openedge-bootstrap
```

Beyond that, everyday configuration is done at runtime. Common tasks:

- **Change the password** — `passwd vagrant` (or `sudo passwd root`), then SSH in with `ssh vagrant@<host>`.
- **Static IP / networking** — set this with the preconfigure menu (`net_mode=static`, plus address, netmask, gateway and DNS); it's baked into `/etc/netplan/50-openedge.yaml` and applied early at boot. To change it at runtime, edit `/etc/netplan/50-openedge.yaml` and `sudo netplan apply`, or use your hypervisor's port-forwarding/NAT rules, or `net_mode=dhcp` if the appliance should keep DHCP.
- **Deploy applications** — run containers as the `vagrant` user (it's in the `docker` group), e.g. `docker run -d -p 8080:80 nginx`; describe multi-container apps with `docker compose`.
- **System packages** — `sudo apt-get update && sudo apt-get install <pkg>`.

For reproducible, fleet-style configuration, layer a provisioning tool (Ansible, cloud-init, or a config-management agent) on top of SSH — the box has Ansible purged from the final image, so install it on the control machine and use a `remote_user: vagrant` playbook.

If you need to change what's baked into the image itself, edit the defaults in the packer template (`ubuntu2404.json` / `ubuntu1804.json`) and `scripts/*.sh`; deployment settings are best changed with the preconfigure menu rather than by hand. The device hostname and user come from the installer answers (`identity` in `http/user-data` for 24.04, `netcfg/get_hostname` plus `preseed.cfg` for 18.04); the memory/CPU and disk size come from the builder settings (currently 1–2 vCPU, 1–2 GB RAM, 80 GB disk).

## Default credentials

The appliance ships with a standard development-box account:

| Field | Value |
| --- | --- |
| User | `vagrant` |
| Password | `vagrant` |
| Passwordless sudo | Yes |
| Docker access | Yes (via the `docker` group) |

Change these before deploying anywhere untrusted.

> **Note:** Ubuntu 18.04 (Bionic) reached end-of-life on 31 May 2023 and 24.04 (Noble) is supported until 2029 — for new deployments use `ubuntu2404.json`. To bump the 24.04 point release, update `iso_urls` and the checksum in `ubuntu2404.json`.