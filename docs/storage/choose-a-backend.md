# Pick a Storage Backend

`oap.storageType` is a required value, and this chart wires up three backends: `elasticsearch`,
`postgresql`, and `banyandb`. This page tells you which to pick, whether the chart can deploy the
backend for you, and exactly what each choice injects into the OAP pods.

## Decision table

| Backend | Pick it when | Chart can deploy it | Enable embedded with | Covered by e2e |
|---|---|---|---|---|
| `banyandb` | You want SkyWalking's purpose-built storage: standalone for small/medium clusters, cluster mode (liaison + data nodes) to scale out. | Yes, via the `skywalking-banyandb-helm` subchart (alias `banyandb`) | `banyandb.enabled=true` (+ `banyandb.image.tag`) | Yes — standalone and cluster |
| `elasticsearch` | You already run Elasticsearch, or you want the chart default and the widest set of OAP query features validated against it. | Yes, via ECK: the `eck-operator` + `eck-elasticsearch` subcharts | `elasticsearch.enabled=true` (**the default**) | Yes |
| `postgresql` | Demo, evaluation, or a tiny single-node install. | Yes, but the embedded deployment is **demo only** | `postgresql.enabled=true` | No |

`postgresql.enabled` is commented in `values.yaml` as *"Whether to start a demo postgresql
deployment, don't use this for production."* — it ships with a hard-coded password (`123456`) and
`primary.persistence.enabled: false`, so the data is lost with the pod. For production PostgreSQL,
run your own server and set `postgresql.enabled=false` with `postgresql.config.host`.

> **`elasticsearch.enabled` defaults to `true`.** If you pick `banyandb` or `postgresql`, also set
> `elasticsearch.enabled=false` — otherwise the chart still installs the ECK operator and a
> 3-node Elasticsearch cluster that nothing uses.

## What each choice actually wires up

Two helpers in `chart/skywalking/templates/_helpers.tpl` do all the work, and both the OAP
Deployment and the [OAP init Job](../operate/oap-init-job.md) include them:

- `skywalking.oap.envs.storage` — the storage env vars on the OAP container.
- `skywalking.containers.wait-for-storage` — an init container that blocks the pod until the
  backend answers.

Every path sets `SW_STORAGE` to `oap.storageType` (rendered through `required`, so an empty value
fails the render). On top of that:

| `oap.storageType` | Env vars added | Readiness gate (init container) |
|---|---|---|
| `elasticsearch` | `SW_STORAGE_ES_CLUSTER_NODES`, plus `SW_ES_USER` / `SW_ES_PASSWORD` (embedded: always; external: only when `elasticsearch.config.user` / `.password` are set) | `busybox` (`initContainer.image`/`tag`, default `busybox:1.30`) running `nc -z` against the ES HTTP port, 60 tries × 5s |
| `postgresql` | `SW_JDBC_URL`, `SW_DATA_SOURCE_USER`, `SW_DATA_SOURCE_PASSWORD` | `postgres:13` running `pg_isready` in a loop with a 3s sleep, no attempt cap |
| `banyandb` | `SW_STORAGE_BANYANDB_TARGETS`, plus `SW_STORAGE_BANYANDB_USER` / `SW_STORAGE_BANYANDB_PASSWORD` when `banyandb.auth.enabled` and `banyandb.auth.users` is non-empty | `curlimages/curl` polling `<http-address>/api/healthz`, 60 tries × 5s |

Anything else you pass to `oap.storageType` is forwarded to `SW_STORAGE` unchanged, but the chart
adds **no** connection env vars and **no** init container for it — you would have to supply the
whole connection yourself through `oap.env` (literal `value:` entries), `oap.extraEnv` (entries may
carry `valueFrom`) or `oap.envFromSecret`.

### Where the connection details come from

| | Embedded (`*.enabled=true`) | External (`*.enabled=false`) |
|---|---|---|
| Elasticsearch | `{release}-elasticsearch-es-http:9200` (name from `elasticsearch.fullnameOverride` when set; the port is hard-coded `9200`, `elasticsearch.config.port.http` applies to external clusters only); user is `elastic`, password read from the ECK-generated secret `{release}-elasticsearch-es-elastic-user`, key `elastic` | `elasticsearch.config.host` + `elasticsearch.config.port.http`; `elasticsearch.config.user` / `.password` are rendered as **plaintext env values**; leave both empty and supply `SW_ES_USER` / `SW_ES_PASSWORD` from a Secret instead, via `oap.envFromSecret` or `oap.extraEnv` — see [Storage credentials from a Secret](../operate/oap-configuration.md#storage-credentials-from-a-secret) |
| PostgreSQL | host `{release}-postgresql`, port `postgresql.containerPorts.postgresql` (`5432`), database `postgresql.auth.database` (`skywalking`) | `postgresql.config.host`; the port, database, username and password still come from `postgresql.containerPorts.postgresql` and `postgresql.auth.*` — there is no `postgresql.config.port` |
| BanyanDB | `{release}-banyandb-grpc:<port>` / `-http:<port>`, ports taken from `banyandb.standalone.*Svc.port` or `banyandb.cluster.liaison.*Svc.port` (defaults `17912` gRPC, `17913` HTTP) | `banyandb.config.grpcAddress` (default `banyandb-grpc:17912`) and `banyandb.config.httpAddress` (default `banyandb-http:17913`) |

## Install examples

BanyanDB (standalone is the chart's default BanyanDB mode):

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  --set oap.image.tag=11.0.0 \
  --set ui.image.tag=horizon-1.0.0 \
  --set oap.storageType=banyandb \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0
```

`banyandb.image.tag` has no default — the subchart fails fast when it is empty. And OAP and
BanyanDB versions are locked: OAP 11.0.0 accepts BanyanDB server API `0.11`, i.e. BanyanDB 0.11.x.
See [Version Compatibility](../evaluate/version-compatibility.md).

Elasticsearch (the default):

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  --set oap.image.tag=11.0.0 \
  --set ui.image.tag=horizon-1.0.0 \
  --set oap.storageType=elasticsearch \
  --set eck-operator.installCRDs=false
```

`eck-operator.installCRDs=false` assumes the ECK CRDs are already in the cluster — install the
`eck-operator-crds` chart first, or drop the flag and let the bundled `eck-operator` install them
(its own default is `installCRDs: true`). See [Elasticsearch](./elasticsearch.md).

PostgreSQL, demo only:

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  --set oap.image.tag=11.0.0 \
  --set ui.image.tag=horizon-1.0.0 \
  --set oap.storageType=postgresql \
  --set elasticsearch.enabled=false \
  --set postgresql.enabled=true
```

## Next

- [Elasticsearch](./elasticsearch.md) — ECK operator, CRDs, node sets, external clusters
- [BanyanDB](./banyandb.md) — standalone vs cluster, auth, version locking
- [PostgreSQL](./postgresql.md) — the demo deployment and pointing at your own server
- [The OAP Init Job](../operate/oap-init-job.md) — how the schema gets created in whichever
  backend you picked
