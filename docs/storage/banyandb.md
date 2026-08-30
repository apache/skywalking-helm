# BanyanDB

How to run SkyWalking on BanyanDB with this chart: the install command, standalone versus cluster
mode, authentication, pointing OAP at an external cluster, and the OAP/BanyanDB version lock you
cannot ignore.

BanyanDB is SkyWalking's own storage engine and the backend the project is moving to. The chart
deploys it as a subchart — [`skywalking-banyandb-helm`](https://github.com/apache/skywalking-banyandb-helm),
pinned to `0.7.0` in `chart/skywalking/Chart.yaml` under the alias `banyandb`, installed only
when `banyandb.enabled=true`.

## Install

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0
```

`elasticsearch.enabled` defaults to `true`, so you must set it to `false` — otherwise the chart
also pulls in the ECK operator and an Elasticsearch cluster that nothing uses.

`banyandb.image.tag` has no default in the subchart; the templates fail fast when it is empty, so
it must always be set. The subchart pulls from `docker.io/apache/skywalking-banyandb`, which
publishes `0.11.0` and `0.11.0-slim` — install the release tag.

This repo's CI pins something else: a GHCR image built from the v0.11.0 *commit* (`test/e2e/env`),
which is the exact source under test — a re-run months from now resolves to the same bits rather
than to a tag that could be re-pushed. To run those same bits:

```shell
  --set banyandb.image.repository=ghcr.io/apache/skywalking-banyandb \
  --set banyandb.image.tag=3b83e18fb0481d02e44eaa5df137fcf7b000754b
```

## Version lock: OAP 11.0.0 accepts API 0.11 only

OAP ships the list of BanyanDB server API versions it will talk to in
`SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS`. **OAP 11.0.0 accepts API `0.11`**, which maps
to BanyanDB release `0.11.x`. Pairing OAP 11 with BanyanDB 0.10.x makes OAP refuse to start with:

```text
Incompatible BanyanDB server API version: 0.10. But accepted versions: 0.11
```

The list is an OAP setting, so `--set oap.env.SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS=0.10`
would suppress the check — do not. It only turns a clear startup failure into schema and query
errors later. Upgrade or downgrade BanyanDB to match. The API-version to release mapping is
published at
[BanyanDB API versions](https://skywalking.apache.org/docs/skywalking-banyandb/latest/installation/versions/).

This is why OAP 11.0.0, Horizon UI horizon-1.0.0 and BanyanDB 0.11.0 move as one set; see
[Version Compatibility](../evaluate/version-compatibility.md).

## Standalone vs cluster

The chart defaults to **standalone**: a single BanyanDB StatefulSet, fine for evaluation and small
installs.

| | standalone (default) | cluster |
|---|---|---|
| `banyandb.standalone.enabled` | `true` | `false` |
| `banyandb.cluster.enabled` | `false` | `true` |
| pods | one `<release>-banyandb` StatefulSet | `<release>-banyandb-liaison` + `<release>-banyandb-data-<role>` StatefulSets, plus the FODC proxy |
| OAP-facing services | unchanged | unchanged |

Cluster mode:

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set banyandb.standalone.enabled=false \
  --set banyandb.cluster.enabled=true
```

Sizing knobs that actually take effect:

| value | default as rendered by this chart |
|---|---|
| `banyandb.cluster.liaison.replicas` | `1` (this chart overrides the subchart's `2`) |
| `banyandb.cluster.data.nodeTemplate.replicas` | `2` (subchart default; per-role overrides live under `banyandb.cluster.data.roles.<role>.replicas`, merged over `nodeTemplate`) |
| `banyandb.cluster.fodc.agent.resources.{requests,limits}` | one entry, `memory` / `256Mi` |

`banyandb.cluster.data.replicas` also appears in this chart's `values.yaml`, but no subchart
template reads it — it is inert. Use the `nodeTemplate` path above.

The FODC agent's `resources.requests` and `resources.limits` are **lists of `{key, value}` pairs**,
not resource maps, so they are set by index:

```shell
  --set banyandb.cluster.fodc.agent.resources.requests[0].key=memory \
  --set banyandb.cluster.fodc.agent.resources.requests[0].value=256Mi \
  --set banyandb.cluster.fodc.agent.resources.limits[0].key=memory \
  --set banyandb.cluster.fodc.agent.resources.limits[0].value=256Mi
```

FODC (First Occurrence Data Collection) is enabled by default in cluster mode and adds a sidecar
agent to liaison and data pods plus an `<release>-banyandb-fodc-proxy` deployment.

## What the chart wires into OAP

`_helpers.tpl` derives the addresses from the subchart's service names and ports — you do not set
them by hand when `banyandb.enabled=true`.

| | value |
|---|---|
| gRPC service | `<release>-banyandb-grpc` port `17912` (`banyandb.standalone.grpcSvc.port`, or `banyandb.cluster.liaison.grpcSvc.port`) |
| HTTP service | `<release>-banyandb-http` port `17913` (`banyandb.standalone.httpSvc.port`, or `banyandb.cluster.liaison.httpSvc.port`) |
| OAP env | `SW_STORAGE=banyandb`, `SW_STORAGE_BANYANDB_TARGETS=<release>-banyandb-grpc:17912` |
| startup gate | a `wait-for-banyandb` init container (`curlimages/curl`) that curls `<http service>/api/healthz` up to 60 times, 5s apart, then fails |

The same init container and the same storage env are attached to both the OAP deployment and the
OAP init job that creates the storage schema — see [The OAP Init Job](../operate/oap-init-job.md).

The `banyandb` name segment comes from the subchart shipping `nameOverride: banyandb`, so the
resources are `<release>-banyandb-*` rather than `<release>-skywalking-banyandb-helm-*`. Set
`banyandb.fullnameOverride` to rename them; the OAP wiring follows it.

Note that the subchart defaults `standalone.httpSvc.type` and `cluster.liaison.httpSvc.type` to
`LoadBalancer`. On a cloud cluster that provisions a public load balancer for BanyanDB's HTTP API.
Set `banyandb.standalone.httpSvc.type=ClusterIP` (or the liaison equivalent) unless you want that.

## Authentication

BanyanDB auth is off by default. Turn it on with `banyandb.auth.enabled=true`:

```shell
  --set banyandb.auth.enabled=true \
  --set banyandb.auth.users[0].username=admin \
  --set banyandb.auth.users[0].password='<a real password>'
```

The chart's own `values.yaml` already ships a placeholder user (`admin` / `banyandb`), so the
example above only needs the password change — but change it.

Two things to know:

- OAP takes its credentials from the **first entry** of `banyandb.auth.users`, rendered into
  `SW_STORAGE_BANYANDB_USER` and `SW_STORAGE_BANYANDB_PASSWORD`. If you set `auth.enabled=true`
  and clear `banyandb.auth.users`, the subchart generates a random `admin` password into its own
  Secret and OAP is given no credentials at all — it will fail to authenticate. Always set the
  users explicitly.
- Those two variables are rendered as **plain env values in the OAP pod spec**, not as a
  `secretKeyRef`. Anyone who can read the deployment or the release values can read the password.
  The chart has no secret-reference path for them today — `oap.env` also takes literal values
  only — so treat the release values as sensitive and restrict RBAC on the namespace.

## External BanyanDB

To point OAP at a BanyanDB cluster the chart does not manage, leave the subchart off and give the
addresses directly:

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=false \
  --set banyandb.config.grpcAddress=banyandb-grpc.data:17912 \
  --set banyandb.config.httpAddress=banyandb-http.data:17913
```

| value | default | used for |
|---|---|---|
| `banyandb.config.grpcAddress` | `banyandb-grpc:17912` | `SW_STORAGE_BANYANDB_TARGETS` |
| `banyandb.config.httpAddress` | `banyandb-http:17913` | the `wait-for-banyandb` health check |

`banyandb.auth.*` still applies in this mode: with `banyandb.auth.enabled=true` the first user in
`banyandb.auth.users` is passed to OAP as the credentials for the external cluster.

## Tuning anything else in BanyanDB

Every parameter of the `skywalking-banyandb-helm` subchart is reachable from this chart by
**prefixing it with `banyandb.`**. `image.tag` becomes `banyandb.image.tag`,
`standalone.resources` becomes `banyandb.standalone.resources`, `storage.data` becomes
`banyandb.storage.data`, and so on — persistence, resources, node discovery, TLS, ingress, the
Canopy console, all of it.

The full parameter list lives in the subchart's own docs:
[skywalking-banyandb-helm configuration](https://github.com/apache/skywalking-banyandb-helm?tab=readme-ov-file#configuration).

For BanyanDB itself — groups, retention, cluster topology, backup — see the
[BanyanDB documentation](https://skywalking.apache.org/docs/skywalking-banyandb/latest/readme/).

## See also

- [Pick a Storage Backend](choose-a-backend.md)
- [Version Compatibility](../evaluate/version-compatibility.md)
- [The OAP Init Job](../operate/oap-init-job.md)
- [Install and Startup Failures](../troubleshooting/install-and-startup.md)
