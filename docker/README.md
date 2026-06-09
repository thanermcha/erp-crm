# GrowERP local

This stack runs the local GrowERP server, PostgreSQL database and Flutter web
clients. The backend also joins the existing OpenClaw LAN network when the
optional override is used.

## Local host names

Add these names to `/etc/hosts` on each machine that will open a web client:

```text
127.0.0.1 backend.growerp.local
127.0.0.1 admin.growerp.local
127.0.0.1 support.growerp.local
127.0.0.1 health.growerp.local
```

For another machine, replace `127.0.0.1` with the GrowERP server's LAN address.
The development TLS certificate is self-signed, so the browser must trust it
before the Flutter clients can call the backend.

Automate both steps on Debian/Ubuntu-based machines with:

```sh
./docker/fix-local-browser-env.sh
```

This script updates `/etc/hosts`, installs `docker/certs/growerp.local.crt`
into the system trust store and prints a browser-oriented probe at the end.

Or do the certificate step manually:

```sh
sudo cp docker/certs/growerp.local.crt /usr/local/share/ca-certificates/growerp-local.crt
sudo update-ca-certificates
```

Chrome and Edge usually pick up the system trust store after that. Firefox may
still require manual certificate import depending on its local trust settings.

## Start

From the repository root:

```sh
docker compose \
  -f docker/docker-compose-dev.yaml \
  -f docker/docker-compose-openclaw.yaml \
  up -d --build
```

Omit `docker/docker-compose-openclaw.yaml` when the OpenClaw network is not
installed on the machine.

The backend image embeds the current local `backend/` tree. Its application
runtime is immutable; PostgreSQL data and sessions are the persistent state
declared by Compose. This prevents old anonymous volumes from hiding newly
built code.

## Local URLs

| Purpose | URL |
| --- | --- |
| Admin client | `https://admin.growerp.local:8443` |
| Support client | `https://support.growerp.local:8443` |
| Health client | `https://health.growerp.local:8443` |
| Backend status | `https://backend.growerp.local:8443/status` |
| Backend direct/internal | `http://127.0.0.1:18082` |
| Backend through OpenClaw proxy | `http://127.0.0.1:18081` |

Use the HTTPS backend URL for login and normal API calls. The direct/internal
HTTP port is useful for health checks, but secure Moqui routes redirect HTTP to
HTTPS.

## Authentication

- Support client: `SystemSupport` / `moqui`, classification `AppSupport`.
- Admin client: use a tenant admin account, classification `AppAdmin`.
- Do not use `SystemSupport` in the Admin client; it is a cross-tenant support
  account and has no Admin tenant setup.

Validate the backend, all three clients and the support login:

```sh
./docker/verify-local.sh
```

This script validates the repository stack and then reports whether the current
machine is also ready for real browser logins. It uses `curl --resolve` and
`-k` for the stack validation itself, so browser prerequisites are reported
separately at the end.

Validate the browser path explicitly from the same machine:

```sh
getent hosts backend.growerp.local admin.growerp.local support.growerp.local health.growerp.local
curl https://backend.growerp.local:8443/status
```

If the second command fails with a certificate error, the hostnames are correct
but the local certificate is still untrusted.

Validate a tenant admin login without storing credentials in the repository:

```sh
GROWERP_ADMIN_USER='admin@example.com' \
GROWERP_ADMIN_PASSWORD='temporary-password' \
./docker/verify-local.sh
```

## Stop and inspect

```sh
docker compose \
  -f docker/docker-compose-dev.yaml \
  -f docker/docker-compose-openclaw.yaml \
  down

docker compose \
  -f docker/docker-compose-dev.yaml \
  -f docker/docker-compose-openclaw.yaml \
  logs -f moqui-server
```

`down` does not remove the bind-mounted PostgreSQL data. Never add `-v` when
the intention is to preserve local data.

## External configuration

SMTP, BirdSend, payment providers and AI provider credentials are intentionally
empty in the development compose file. Configure them before validating the
corresponding integrations.
