# Version Compatibility

Which OAP, UI and storage versions go together for chart **5.0.0**. Only two pairings are actually constrained — OAP↔BanyanDB (hard, OAP refuses to start) and OAP↔Horizon UI (soft, two settings) — everything else is a free choice within the ranges below.

## The tested set

This is the combination every cell in `test/e2e/` installs on each CI run, so it is the set the chart is best known to work with. The OAP 10.4 line described further down is documented but **not** covered by CI.

| Component | Version | Where you set it |
|---|---|---|
| SkyWalking OAP | `11.0.0` | `oap.image.tag` — **required**, no default |
| Horizon UI | `horizon-1.0.0` | `ui.image.tag` — **required**, no default |
| BanyanDB | `0.11.0` (CI pins a GHCR build of that commit — see the note below) | `banyandb.image.tag` — **required** when `banyandb.enabled=true` |
| `skywalking-banyandb-helm` subchart | `0.7.0` | `chart/skywalking/Chart.yaml` dependency |
| Elasticsearch (ECK-managed) | `8.18.8` | `elasticsearch.version` |
| `eck-operator` / `eck-elasticsearch` charts | `3.3.1` / `0.18.1` | `chart/skywalking/Chart.yaml` dependencies |
| PostgreSQL (Bitnami chart `12.1.2`, demo only) | appVersion `15.1.0` | `chart/skywalking/Chart.yaml` dependency |
| Satellite | optional, `satellite.enabled=false` by default (CI enables it with a GHCR commit build, not a release tag) | `satellite.image.tag` |
| Kubernetes | `v1.28.15` — every e2e cell runs `test/e2e/kind28.yaml` (`kindest/node:v1.28.15`) | your cluster |

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0
```

> Install `docker.io/apache/skywalking-banyandb:0.11.0`; `0.11.0-slim` is published too. CI pins a GHCR build of the `v0.11.0` commit instead, as the exact source under test: a re-run resolves to the same bits rather than to a re-pushable tag. See the comments in `test/e2e/env`.

## OAP and BanyanDB are locked together

OAP ships the list of BanyanDB **server API** versions it accepts in `config/bydb.yml`:

```yaml
compatibleServerApiVersions: ${SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS:"0.11"}
```

If the server advertises anything else, OAP does not start:

```
ERROR [] - ... Incompatible BanyanDB server API version: 0.10. But accepted versions: 0.11
org.apache.skywalking.oap.server.library.module.ModuleStartException: Incompatible BanyanDB server API version...
```

| OAP | Accepted server API | BanyanDB release |
|---|---|---|
| `11.0.0` | `0.11` | `0.11.x` |
| `10.4.0` | `0.10` | `0.10.x` |

So **OAP 11 requires BanyanDB 0.11.x**. Pairing it with 0.10.x fails at boot, and there is no forward or backward slack — the setting is a comma-separated list of exact API versions, not a range, and the default ships exactly one. The API-version-to-release mapping is published upstream at [BanyanDB API versions](https://skywalking.apache.org/docs/skywalking-banyandb/latest/installation/versions/).

Because of this, `oap.image.tag` and `banyandb.image.tag` must move in the same `helm upgrade`. Overriding `SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS` via `oap.env` to force an unlisted pairing is not supported — see [BanyanDB](../storage/banyandb.md).

## OAP and Horizon UI

Horizon UI releases on its own cadence; there is no 1:1 version mapping with OAP. Pin `ui.image.tag=horizon-1.0.0` whichever OAP you run.

| OAP | Horizon `1.0.0` | Extra configuration |
|---|---|---|
| `11.x` | Native — full feature set | None — the chart's defaults are correct |
| `10.3` – `10.4` | Partial — data plane only | `ui.config.templates.mode: readonly` **and** `oap.ports.admin: null` |
| `< 10.3` | Partial, with query gaps | As above; Horizon sends `queryTrace(..., duration)` (OAP 10.3+) and `findEndpoint(..., duration)` (OAP 10.2+) with no fallback |

Against **OAP 10.x**, Horizon cannot read dashboard templates from OAP (the `/ui-management/templates*` admin REST API is an OAP 11 addition), so it must fall back to the templates bundled in its image:

```yaml
ui:
  config:
    templates:
      mode: readonly
```

Dashboards, traces, logs, topology, alarms and profiling all work over the query port. OAP 10 has no admin server at all — `admin-server` (`SW_ADMIN_SERVER_PORT`, default `17128`) and the modules that mount on it (`ui-management`, `receiver-runtime-rule`, `dsl-debugging`, `inspect`) first appear in OAP 11 — so Inspect, DSL Management, Live Debugger, the read-only alarm-rule catalog (backed by `/status/alarm/*` on that same port) and Cluster Status → Admin do not appear. Horizon probes each admin route on demand rather than checking a version number.

So on any 10.x OAP, also drop the admin port from the chart's Service and Deployment:

```yaml
oap:
  ports:
    admin: null
```

With the port unset the chart omits `adminUrl` from `horizon.yaml` entirely, so Horizon simply never probes an admin host. Leaving the port at its default would be worse than useless on 10.x: 17128 there is the AI-pipeline URI-recognition server, not an admin API. See [Horizon UI in This Chart](../ui/horizon-ui.md).

## The legacy booster UI is not an option

`skywalking-booster-ui` (and `skywalking-rocketbot-ui` before it) is **not supported by this chart or by SkyWalking**. OAP 11.0.0 deleted `apm-webapp/` and the `skywalking-ui` submodule from the distribution, along with the `docker.ui` build target.

- The last booster image published to `apache/skywalking-ui` is `10.4.0`. **There is no `11.x` tag and there will not be one** — every new tag in that repository is `horizon-x.y.z`.
- The OAP surfaces booster relied on are gone too: the `ui-initialized-templates` seed files, sidebar menu storage, the `UIConfigurationManagement` GraphQL mutations, and `SW_ENABLE_UPDATE_UI_TEMPLATE`.

`ui.image.tag` must be a `horizon-*` tag. If you are upgrading from a chart release that set `ui.image.tag=<oap-version>`, see [Upgrading](../upgrade/upgrading.md) — Horizon also requires configured users, with no `admin/admin` fallback.

## Storage backend version ranges

The chart does not constrain these; OAP does.

| Backend | Supported by OAP 11 | What the chart deploys |
|---|---|---|
| BanyanDB | `0.11.x` only (see above) | subchart, `banyandb.image.tag` required |
| Elasticsearch | 7.x, 8.x, 9.x | ECK-managed `8.18.8` (`elasticsearch.version`) |
| OpenSearch | 1.x, 2.x, 3.x (upstream tests 1.3.10, 2.4.0, 2.8.0, 3.0.0) | not deployed — connect as external ES |
| PostgreSQL | 8.2 or newer (JDBC driver 42.3.2) | Bitnami subchart, PG `15.1.0`, **demo only** |

Details: [Elasticsearch](../storage/elasticsearch.md), [BanyanDB](../storage/banyandb.md), [PostgreSQL](../storage/postgresql.md), and the upstream [OAP storage docs](https://skywalking.apache.org/docs/main/latest/en/setup/backend/backend-storage/).

## Kubernetes and Helm

- **Helm 3 or newer**, and **3.8 or newer** for the `oci://` install above. Chart `5.0.0` is `apiVersion: v2`, which rules out Helm 2; the chart README and [Quick Start](../install/quick-start.md) both list 3.8+ because the chart is only published as an OCI artifact.
- All five e2e cells run on one kind config, `test/e2e/kind28.yaml` — **`kindest/node:v1.28.15`**, a control plane and three workers. The chart declares no `kubeVersion` constraint.

## Before you change a version

1. Move `oap.image.tag` and `banyandb.image.tag` together, in one `helm upgrade`.
2. Keep `ui.image.tag` on a `horizon-*` tag; it can lag or lead OAP.
3. Elasticsearch and PostgreSQL upgrades are subchart concerns — follow ECK / Bitnami procedures, not this chart.

If OAP crash-loops after a version change, the `Incompatible BanyanDB server API version` section of [Install and Startup Failures](../troubleshooting/install-and-startup.md) covers it.
