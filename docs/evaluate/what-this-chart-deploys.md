# What This Chart Deploys

What a `helm install` of `chart/skywalking` actually creates in your cluster, which pieces are
optional, and which value key turns each one on or off.

This repository ships one chart, `chart/skywalking`, published as `skywalking-helm`. A single
release of it carries the OAP backend, Horizon UI, and — when you ask for them — Satellite and a
storage backend running as a subchart. Everything below is about that one release.

## A default install

Three values have no defaults and must be supplied every time: `oap.image.tag`,
`oap.storageType`, `ui.image.tag`.

```shell
helm install skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0
```

With everything else left at its default (`elasticsearch.enabled=true`), that release contains:

| kind | name (release `skywalking`) | notes |
|---|---|---|
| Deployment | `skywalking-skywalking-helm-oap` | `oap.replicas: 2`, runs `-Dmode=no-init` |
| Job | `skywalking-skywalking-helm-oap-init-<hash>` | one-shot, runs `-Dmode=init` to create the storage schema |
| Service | `skywalking-skywalking-helm-oap` | ClusterIP; ports `11800`, `12800`, `17128` |
| Deployment | `skywalking-skywalking-helm-ui` | `ui.replicas: 1`, `strategy: Recreate` |
| Service | `skywalking-skywalking-helm-ui` | ClusterIP, `80` → container `8081` |
| ConfigMap | `skywalking-skywalking-helm-ui` | only when `ui.config` is set — the rendered `horizon.yaml`, mounted over the image's |
| ServiceAccount | `skywalking-skywalking-helm-oap` | used by both the OAP Deployment and the init Job |
| Role + RoleBinding | `skywalking-skywalking-helm` | `get/watch/list` on pods, configmaps |
| ClusterRole + ClusterRoleBinding | `skywalking-skywalking-helm` | `get/watch/list` on pods, pods/log, endpoints, services, nodes, namespaces, configmaps, deployments, replicasets, Istio `serviceentries` |
| ECK operator | `elastic-operator` StatefulSet, webhook Service/Secret, CRDs, RBAC | from the `eck-operator` subchart |
| Elasticsearch | `skywalking-elasticsearch` | ECK custom resource, version `8.18.8`, one nodeSet of `3` |

Resource names are `<release>-<chart name>` (`skywalking-helm`) plus a component suffix, unless you
set `nameOverride` / `fullnameOverride`.

> The `eck-operator` subchart carries the ECK CRDs (`eck-operator.installCRDs`, default `true`),
> but they are ordinary templates — Helm cannot apply a CRD and an `Elasticsearch` custom resource
> of that kind in the same release. On a cluster that has never run ECK, install the CRDs first and
> then add `--set eck-operator.installCRDs=false`. Steps in
> [Elasticsearch](../storage/elasticsearch.md).

## Components and their switches

| component | value key | default | what it renders |
|---|---|---|---|
| OAP Deployment + Service | — | always | `oap-deployment.yaml`, `oap-svc.yaml` |
| OAP init Job | — | always | `oap-init.job.yaml`, a normal release resource (not a Helm hook) |
| OAP ServiceAccount + RBAC | `serviceAccounts.oap.create` | `true` | ServiceAccount, Role, RoleBinding, ClusterRole, ClusterRoleBinding |
| OAP config-override ConfigMap | `oap.config` | `{}` (nothing) | `<fullname>-oap-cm-override`, mounted into `/skywalking/config` |
| OAP dynamic-config ConfigMap | `oap.dynamicConfig.enabled` | `false` | `skywalking-dynamic-config` + `SW_CONFIGURATION=k8s-configmap` |
| Horizon UI Deployment, Service, ConfigMap | `ui.enabled` | `true` | all UI resources; `false` deploys OAP only |
| UI Ingress | `ui.ingress.enabled` | `false` | `ui-ingress.yaml` |
| UI PersistentVolumeClaim | `ui.persistence.enabled` | `false` | `<fullname>-ui-data` for `/data`; otherwise an `emptyDir` |
| Satellite | `satellite.enabled` | `false` | Deployment, Service, ServiceAccount, Role, RoleBinding |
| Satellite config override | `satellite.config` | `{}` (nothing) | `<fullname>-satellite-cm-override` |
| Elasticsearch (ECK operator + cluster) | `elasticsearch.enabled` | `true` | `eck-operator` and `eck-elasticsearch` subcharts |
| PostgreSQL | `postgresql.enabled` | `false` | Bitnami `postgresql` subchart (demo only, no persistence by default) |
| BanyanDB | `banyandb.enabled` | `false` | `skywalking-banyandb-helm` subchart; also needs `banyandb.image.tag` |

`elasticsearch.enabled` and `oap.storageType` are independent. If you switch `oap.storageType` to
`banyandb` or `postgresql`, also set `elasticsearch.enabled=false` — otherwise the chart still
deploys an Elasticsearch cluster that nothing uses.

## What OAP gets out of the box

- **Init container.** Every OAP pod and the init Job start with an init container that blocks until
  the backend answers — `wait-for-elasticsearch` (`busybox:1.30` + `nc`), `wait-for-postgresql`
  (`postgres:13` + `pg_isready`), or `wait-for-banyandb` (`curlimages/curl` against
  `/api/healthz`).
- **Two modes.** The Deployment runs `-Dmode=no-init` and keeps port `12800` closed until the
  schema exists; the Job runs `-Dmode=init` and creates it. See
  [The OAP Init Job](../operate/oap-init-job.md).
- **Cluster coordination.** `SW_CLUSTER=kubernetes` with `SW_CLUSTER_K8S_NAMESPACE` and a label
  selector — that is what the ServiceAccount and RBAC above are for.
- **JVM.** `oap.javaOpts` defaults to `-Xmx2g -Xms2g`; `oap.resources` is empty (no requests or
  limits) by default.
- **Storage env.** `SW_STORAGE` plus the backend-specific variables are derived from
  `oap.storageType` and whether the backend is embedded or external.
- **Probes.** Liveness/readiness are TCP on `12800`; the startup probe allows `30 × 10s` so a cold
  start can wait for the init Job.

## Ports

| service | port | value key | purpose |
|---|---|---|---|
| OAP | `11800` | `oap.ports.grpc` | agent / Satellite gRPC ingest |
| OAP | `12800` | `oap.ports.rest` | HTTP ingest + GraphQL query |
| OAP | `17128` | `oap.ports.admin` | admin REST (`/status/*`, `/debugging/*`, the `ui-management` template store Horizon reads in `live` mode); OAP 11 only — set `null` on OAP 10.x |
| UI | `80` → `8081` | `ui.service.externalPort` / `ui.service.internalPort` | Horizon BFF |
| Satellite | `11800` | `satellite.ports.grpc` | agent gRPC ingest |
| Satellite | `1234` | `satellite.ports.prometheus` | Satellite self-telemetry |

`oap.ports` is a free-form map: add `zipkin-receiver`, `zipkin-query`, `promql`, `logql`, `traceql`
or `metrics` entries and they are opened on both the container and the Service. Setting
`zipkin-receiver` / `zipkin-query` additionally sets the matching `SW_RECEIVER_ZIPKIN*` /
`SW_QUERY_ZIPKIN*` environment variables, and `zipkin-query` makes the chart wire Horizon's
`oap.zipkinUrl`.

## Optional: Satellite

A gateway that fronts OAP for agent traffic. Off by default; it needs its own image tag.

```shell
helm install skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set satellite.enabled=true \
  --set satellite.image.tag=v0.4.0
```

Agents then point at the Satellite Service instead of the OAP one. See
[Satellite Gateway](../operate/satellite.md).

## Optional: an embedded storage backend

| backend | enable | what lands in the release |
|---|---|---|
| Elasticsearch | `elasticsearch.enabled=true` (default) | ECK operator + an `Elasticsearch` CR (`8.18.8`, 3 nodes) |
| BanyanDB | `banyandb.enabled=true` + `banyandb.image.tag` | StatefulSet, ServiceAccount, a `-grpc` ClusterIP Service (`17912`) and a `-http` Service (`17913`, type `LoadBalancer` by default) |
| PostgreSQL | `postgresql.enabled=true` | Bitnami PostgreSQL — demo defaults, persistence disabled |

Set the corresponding `*.enabled` to `false` and fill in `*.config.*` to point OAP at an existing
external instance instead. Details per backend:
[Elasticsearch](../storage/elasticsearch.md), [BanyanDB](../storage/banyandb.md),
[PostgreSQL](../storage/postgresql.md), or start at
[Pick a Storage Backend](../storage/choose-a-backend.md).

## What this chart does *not* deploy

- **Any login for the UI.** Horizon ships no default credentials and does not fail closed — the pod
  goes Ready and nobody can sign in. Configure users: [Set Up Logins](../ui/logins.md).
- **Agents or instrumentation.** You install those with your applications.
- **An ingress controller or a StorageClass.** `ui.ingress.enabled` renders an Ingress object but
  installs no controller, and every claim the release makes falls back to the cluster's default
  StorageClass. See [Requirements](requirements.md).
- **Storage you sized yourself.** The chart's ES nodeSet ships without `volumeClaimTemplates`, so
  ECK falls back to its own default claim (1Gi on the default StorageClass) — enough to start, not
  enough to keep. The PostgreSQL subchart is set to `primary.persistence.enabled: false`, so that
  one really is ephemeral.

Every value in the table above, with its full description, is in the
[Chart Values reference](../reference/skywalking-chart-values.md).
