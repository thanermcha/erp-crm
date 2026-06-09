# GrowERP Local Implementation Status

Date: 2026-06-04  
Branch observed: `integracao`

## Executive status

The local GrowERP core is operational after consolidating the active server
with the persistent PostgreSQL data created on 2026-06-03.

Before consolidation, two independent GrowERP stacks existed:

- the current repository stack served the latest code but used a new database;
- the OpenClaw-integrated stack retained the tenant and user data but its
  backend container was stopped.

This explained why `SystemSupport` behaved differently between clients and why
the user created on 2026-06-03 could not be found in the active server.

The backend image also declared application runtime directories as anonymous
Docker volumes. Compose preserved those volumes during recreation, causing old
component code and seed data to hide newly built code. The runtime is now
immutable in the image, with persistence limited to state explicitly declared
by Compose.

## Current architecture

| Component | Current implementation | Status |
| --- | --- | --- |
| Backend | Moqui, container `moqui`, current repository image | Operational |
| Database | PostgreSQL 17.2, container `postgres`, persistent bind mount | Operational and consolidated |
| Reverse proxy | nginx-proxy, HTTPS on host port `8443` | Operational |
| Admin client | Flutter web, classification `AppAdmin` | Operational |
| Support client | Flutter web, classification `AppSupport` | Operational |
| Health client | Flutter web, classification `AppHealth` | Operational |
| OpenClaw integration | Backend joins `openclaw-ai_openclaw-lan` as `growerp-backend` | Operational |

The canonical client API URL is
`https://backend.growerp.local:8443`. Port `18082` is a direct internal HTTP
endpoint and port `18081` is the existing OpenClaw HTTP proxy; neither should
replace the canonical HTTPS URL in the web clients.

## Authentication status

- `SystemSupport` is a support account and authenticates with `AppSupport`.
- Tenant administrators authenticate with `AppAdmin`.
- The tenant `GROWERP` is complete and linked to the company
  `Cloud Facilities - BL Software`.
- The tenant admin created on 2026-06-03 is present and authenticates.

Security seed corrections made during stabilization:

- corrected the system support member key from `SystemSupport` to
  `SYSTEM_SUPPORT`;
- assigned fixed dates to support classifications to stop duplicate records on
  each INSTALL load;
- separated the Moqui `ADMIN` REST authorization ID from the GrowERP system
  authorization ID.
- embedded the current local backend in the server image and removed stale
  anonymous application-runtime volumes.

## Planning versus implementation

Several planning documents mark an architecture or specification as complete.
That does not always mean the corresponding feature is production-operational.
The current repository contains substantial implementation beyond the original
ERP core:

- assessment and landing-page entities, services and Flutter packages;
- dynamic menus and GenUI onboarding backed by Gemini;
- marketing, social posts and outreach campaign flows;
- CRM/Freelabot seed data and integration design;
- manufacturing routing, work orders and liner-panel functionality;
- MCP and ADK agent entities, prompts and seed data;
- locale and timezone support, configured locally for `pt_BR` and
  `America/Belem`.

The core server, tenant data and local Admin/Support authentication are
operational. Some feature packages remain partially implemented or require
external services before they can be called operational end to end.

## External dependencies still required

- SMTP credentials for email delivery and password reset.
- Gemini or other LLM credentials for GenUI onboarding and AI flows.
- BirdSend configuration for configured marketing automation.
- Stripe/payment provider credentials for payment flows.
- Browser MCP/platform credentials for LinkedIn and Twitter outreach.
- A trusted LAN TLS certificate or local CA before rollout to other machines.

## Verification and rollout

Use:

```sh
./docker/verify-local.sh
```

This validates backend health, Admin/Support/Health client configuration and
the support login. Then follow [`docker/README.md`](../docker/README.md) to
start the complete stack and configure the local host names. Before integrating
another machine, replace loopback host entries with the server LAN address and
validate HTTPS, support login and tenant admin login from that machine.
