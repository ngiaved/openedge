# openedge sample edge stack

A self-contained sample you can point an `openedge` appliance at. It shows the
three bits the appliance pulls at boot and the **standard names** it expects:

> This is also the **default stack**: with zero configuration, an appliance built
> from this repository downloads this `docker-compose.yml` at first boot and
> runs `docker compose up -d`.

| File | Standard appliance path | Purpose |
| --- | --- | --- |
| `docker-compose.yml` | `/opt/openedge/docker-compose.yml` | The bot / workload stack |
| `runmeonboot` | `/opt/openedge/runmeonboot` | User script executed on every boot |
| `edge-login.sh` | `/opt/openedge/edge-login.sh` | Device registration/login script |

## Deploy

Host this folder anywhere `curl` can reach (plain HTTP server, S3, GCS) and
configure the appliance:

```sh
cd ..
./preconfigure/preconfigure.sh --set url=https://example.com/docker-compose.yml \
  --set boot_script_url=https://example.com/runmeonboot \
  --set login_url=https://example.com/edge-login.sh --save
packer build ubuntu2404.json
```

At boot the appliance runs, in order:
`edge-login.sh` → `runmeonboot` → `docker compose up -d`.

## What the sample does

- `edge-login.sh` — idempotently assigns a device id (from `/etc/machine-id`)
  and writes a heartbeat log; replace with your real registration endpoint.
- `runmeonboot` — logs host facts (docker version, disk free) to
  `/var/log/openedge-runmeonboot.log`; replace with real host preparation.
- `docker-compose.yml` — runs `busybox` logging `hello-edge` every minute, so
  you can verify the stack is alive with `docker ps` / `docker logs hello-edge`.

Try it locally without the appliance:

```sh
docker compose up -d && docker logs -f hello-edge
```