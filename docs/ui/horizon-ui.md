# Horizon UI in This Chart

This page explains what web UI the chart deploys, how it talks to OAP, and why the legacy booster UI is no longer an option.

[Apache SkyWalking Horizon UI](https://github.com/apache/skywalking-horizon-ui) is the official SkyWalking web console and the only UI this chart deploys. It is a Vue SPA served by a Node **BFF** (backend-for-frontend) inside the same container — not a thin reverse proxy like the UI it replaces.

## What the chart ships

| | value | set by |
|---|---|---|
| image | `skywalking.docker.scarf.sh/apache/skywalking-ui` | `ui.image.repository` |
| tag | required, no default; a `horizon-*` tag on the default repository (e.g. `horizon-1.0.0`) | `ui.image.tag` |
| container port | `8081` | `ui.service.internalPort` |
| service port | `80` → `8081` | `ui.service.externalPort` |
| replicas | `1` | `ui.replicas` |
| config file | ConfigMap mounted at `/app/horizon.yaml` | `ui.config` (empty by default) |

Set `ui.enabled: false` to skip the UI entirely — no Deployment, Service, Ingress, ConfigMap or PVC is created, and OAP stays reachable on its own query port.

## The BFF talks to OAP on two ports

Booster UI needed only the GraphQL query port. Horizon's BFF needs two, and the chart writes both into `horizon.yaml`:

| field | OAP port | chart value | what it carries |
|---|---|---|---|
| `oap.queryUrl` | `12800` | `oap.ports.rest` | the GraphQL query API |
| `oap.adminUrl` | `17128` | `oap.ports.admin` | `/status/*`, `/debugging/*`, inspect, DSL debugging, runtime rules, dashboard templates |
| `oap.zipkinUrl` | commented out by default | `oap.ports.zipkin-query` | written as `http://<oap>:<port>/zipkin`, only when that port is set |

OAP 11 serves the admin surfaces **only** on the admin port, so `oap.ports.admin` is required. It defaults to `17128`. Set it to `null` on any OAP 10.x release — the admin server arrived in OAP 11, and on 10.x that port belongs to the AI-pipeline URI-recognition server.

A rendered `horizon.yaml` for release `skywalking` looks like this:

```yaml
oap:
  adminUrl: ${HORIZON_OAP_ADMIN_URL:http://skywalking-skywalking-helm-oap:17128}
  queryUrl: ${HORIZON_OAP_QUERY_URL:http://skywalking-skywalking-helm-oap:12800}
server:
  port: 8081
```

Every chart-computed field is written as a `${VAR:default}` **token**, so the in-cluster address is the default and the matching `HORIZON_*` environment variable still overrides it. `server.port` is the one exception — it is derived from `ui.service.internalPort` so the BFF binds the port the container actually exposes.

When `ui.ingress.enabled` is true and `ui.ingress.hosts` is non-empty the chart writes one more field, `server.publicUrl` — `${HORIZON_PUBLIC_URL:<scheme>://<first host>}`, `https` when `ui.ingress.tls` is non-empty, `http` otherwise. Horizon otherwise derives its public base URL per request, which is wrong behind an ingress that rewrites `Host`. See [UI service and ingress](../expose/ui-service-and-ingress.md).

## Port 8081, and no `/graphql` passthrough

Two breaking differences from booster UI:

- The container listens on **8081** (booster listened on 8080). The Service still fronts it on port 80.
- The BFF **does not proxy `/graphql`** to OAP. Anything that used to query the UI's GraphQL endpoint must now address the OAP service directly.

```shell
# before: swctl --base-url=http://<ui>/graphql ...
swctl --display yaml \
  --base-url=http://skywalking-skywalking-helm-oap:12800/graphql \
  service ls
```

The chart's own e2e suite goes one step further: every assertion runs through Horizon's own API rather than OAP's GraphQL, so it exercises the same path a browser does.

Both probes target the container's named `page` port, so they follow `ui.service.internalPort` automatically — the readiness probe uses `/api/auth/health`, the only unauthenticated BFF endpoint.

The Deployment uses `strategy: Recreate` and defaults to one replica: the BFF keeps its session table in memory, so two pods serving at once means logins break on alternating requests unless your ingress does sticky routing.

## Image tags

Horizon releases **independently** of OAP — there is no 1:1 version mapping, and you pin the two tags separately.

| channel | image | tags |
|---|---|---|
| release | `apache/skywalking-ui` (Docker Hub) | `horizon-x.y.z`, e.g. `horizon-1.0.0` |
| dev / pre-release | `ghcr.io/apache/skywalking-horizon-ui` | full commit SHA, `x.y.z`, `main` |

Note the asymmetry: the same version is `horizon-1.0.0` on Docker Hub and `1.0.0` on ghcr.io.

Horizon 1.0.0 works against OAP 10.4.0 as well as OAP 11.x, so pin it whichever OAP release you run. Against a 10.x OAP also set `ui.config.templates.mode: readonly` (or `HORIZON_TEMPLATES_MODE=readonly`) — Horizon reads dashboard templates from OAP 11's `/ui-management` admin REST API, which OAP 10 does not serve, so `readonly` renders the templates bundled in the image instead.

## Booster UI is not supported

The legacy `skywalking-booster-ui` (and `skywalking-rocketbot-ui` before it) is not supported by this chart, and that is not a chart policy — SkyWalking 11.0.0 removed the UI from the distribution:

- `apm-webapp/` — the Armeria reverse proxy behind the `skywalking/ui` image — was deleted, along with the `skywalking-ui` git submodule tracking `apache/skywalking-booster-ui`, the `docker.ui` Maven target, and the image build.
- The last booster image published to `apache/skywalking-ui` is therefore `10.4.0`. There is no `11.x` tag and there will not be one; the repository now carries only `horizon-x.y.z` tags.
- The OAP-side surfaces booster depended on are gone too: the `ui-initialized-templates` seed files, the sidebar menu storage, the `UIConfigurationManagement` GraphQL mutations and queries, and the `SW_ENABLE_UPDATE_UI_TEMPLATE` flag. Horizon ships its own dashboard library and menu, and manages templates over the admin REST port.

### Upgrading from a chart release that ran booster UI

1. Replace `--set ui.image.tag=<oap-version>` with `--set ui.image.tag=horizon-1.0.0`.
2. Make sure `oap.ports.admin` is set (it is, by default).
3. Repoint any `swctl` / API caller from `http://<ui>/graphql` to `http://<oap>:12800/graphql`.
4. Configure login users — see [Set up logins](logins.md).

## Authentication is not optional

Horizon has **no built-in `admin/admin` fallback** and no login configured by default. The BFF does not fail closed: with no users it still boots, logs an error, serves the login page, and answers the readiness probe with 200 — so the pod reports **Ready and nobody can log in**. Configure users before you rely on the deployment — see [Set up logins](logins.md).

Prefer environment variables (`ui.extraEnv`, `ui.envFromSecret`) over `ui.config`: the image's `/app/horizon.yaml` is fully env-tokenized, and any field you write as a plain literal makes its `HORIZON_*` variable inert. `${VAR}` tokens written in `ui.config` do expand, which is how the Secret pattern works:

```yaml
ui:
  envFromSecret: horizon-admin   # provides HORIZON_ADMIN_HASH
  config:
    auth:
      local:
        users:
          - username: admin
            passwordHash: "${HORIZON_ADMIN_HASH}"
            roles: [admin]
```

## See also

- [Set up logins](logins.md) — the demo credentials snippet and the production Secret pattern
- [Configure Horizon](configure.md) — `ui.config` vs `ui.extraEnv`, persistence, extra volumes
- [Quick start](../install/quick-start.md) — a full install command with the required values
- [`horizon.yaml` reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md) — the full upstream schema (server, templates, oap, auth, rbac, session, audit, ai, mcp, oauth, debugLog)
- [Apache SkyWalking Horizon UI](https://github.com/apache/skywalking-horizon-ui) — upstream repository
