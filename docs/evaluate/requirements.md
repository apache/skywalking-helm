# Requirements

What your cluster and workstation need before `helm install`, and the one pre-install step the
default (Elasticsearch) path requires.

## Kubernetes and Helm

| Requirement | Version | Where it comes from |
|---|---|---|
| Kubernetes | 1.21+ | `eck-operator` 3.3.1 and `eck-elasticsearch` 0.18.1 both declare a `kubeVersion` floor of `1.21.0-0`; `chart/skywalking` itself declares none. Helm does **not** enforce a *subchart's* `kubeVersion`, so an older cluster still installs — it just runs an unsupported ECK. |
| Helm | 3.8+ (4.x also works) | The chart is `apiVersion: v2`, and `helm dep up` pulls the BanyanDB dependency from an OCI registry (`oci://registry-1.docker.io/apache`), which needs Helm's non-experimental OCI support (3.8.0). |
| `kubectl` | matching your cluster | Used to watch the install (`kubectl get pods -w`) and for all troubleshooting. |

CI exercises the chart on a four-node [kind](https://kind.sigs.k8s.io/) cluster running
`kindest/node:v1.28.15` (`test/e2e/kind28.yaml`) — every e2e cell uses it — so 1.28 is the
version with the most coverage.

The chart adapts to older Ingress APIs (`ui-ingress.yaml` falls back from
`networking.k8s.io/v1` to `v1beta1` to `extensions/v1beta1`), so ingress itself is not what sets
the minimum.

## Cluster permissions

Installing needs more than namespace-scoped rights:

- **CRDs are cluster-scoped.** The ECK CRDs (see below) can only be installed by a user with
  cluster-admin-level permissions.
- **The chart creates a `ClusterRole` and `ClusterRoleBinding`** for OAP (`oap-clusterrole.yaml`,
  `oap-clusterrolebinding.yaml`), granting `get`/`watch`/`list` on pods, pod logs, endpoints,
  services, nodes, namespaces, configmaps, `extensions` deployments/replicasets and Istio
  `networking.istio.io` `serviceentries` — this is what backs Kubernetes-based service discovery
  and mesh analysis. Both templates are gated on `serviceAccounts.oap.create`, so set
  `serviceAccounts.oap.create=false` and supply your own `serviceAccounts.oap.name` if you cannot
  create cluster-scoped RBAC.

## Storage volumes

Only Elasticsearch and a BanyanDB *cluster* claim persistent volumes out of the box. The other
paths render `emptyDir` — fine for a trial, data loss on every pod restart anywhere else:

| Component | Claims a PV by default? | Note |
|---|---|---|
| Elasticsearch (ECK) | Yes | `elasticsearch.nodeSets[0].count: 3`, and because `volumeClaimTemplates` is left commented out ECK applies its own default — a 1Gi `elasticsearch-data` PVC per node on the default StorageClass. Uncomment `elasticsearch.nodeSets[].volumeClaimTemplates` in `values.yaml` to size it (the example asks for 30Gi). See [ECK volume claim settings](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html). |
| BanyanDB standalone (`banyandb.standalone.enabled: true`, the default) | **No** | The subchart ships `storage.standalone.enabled: false`. Set `banyandb.storage.standalone.enabled=true` to claim the 200Gi `standalone-data` volume. |
| BanyanDB cluster (`banyandb.cluster.enabled=true`) | Yes | `banyandb.storage.data.enabled: true` — five data PVCs (50Gi/50Gi/5Gi/50Gi/5Gi) plus 10Gi for liaison, all with `storageClass: null`, i.e. the cluster default StorageClass. |
| PostgreSQL | **No** | This chart overrides the Bitnami `postgresql` 12.1.2 defaults with `postgresql.primary.persistence.enabled: false` and `postgresql.readReplicas.persistence.enabled: false`; the data directory is an `emptyDir`. It is a demo backend, as `values.yaml` says. |
| Horizon UI | No | `ui.persistence.enabled: false` (1Gi, `ReadWriteOnce` once enabled). Turn it on to keep BFF audit log, setup state and alarm state across restarts. |

`oap.resources`, `ui.resources` and `satellite.resources` are all `{}` by default — no requests or
limits are set, so plan capacity yourself. For a laptop-sized cluster, drop the Elasticsearch node
count to 1 the way `test/e2e/values.yaml` does.

## Install the ECK CRDs first

**When you need this:** `elasticsearch.enabled=true`, which is the **default**. The
`eck-operator-crds` chart ships the CRDs as ordinary templates, so without this step they would be
created in the same install that also renders the `Elasticsearch` custom resource depending on
them. Install them as their own release first — `SKYWALKING_RELEASE_NAMESPACE` is the namespace you
install into, exported as in [Quick Start](../install/quick-start.md):

```shell
helm dep up chart/skywalking
tar xzf chart/skywalking/charts/eck-operator-3.3.1.tgz -C /tmp eck-operator/charts/eck-operator-crds
helm install eck-crds /tmp/eck-operator/charts/eck-operator-crds \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" --create-namespace
```

Then install the chart with `eck-operator.installCRDs=false` so the operator does not try to create
the same cluster-scoped CRDs again:

```shell
helm install skywalking chart/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

Pass `installCRDs=false` for the same reason if the ECK CRDs are already present because someone
else installed ECK in the cluster — they are global resources, and a second chart owning them would
overwrite them on upgrade and delete them on uninstall.

The `eck-crds` release is independent of the SkyWalking release: `helm uninstall skywalking` leaves
the CRDs in place, and uninstalling `eck-crds` deletes every ECK-managed Elasticsearch in the
cluster.

**When you do NOT need this:** any install with `elasticsearch.enabled=false` — no ECK operator, no
CRDs. Note that `elasticsearch.enabled` is the *only* switch: the dependency condition is
`elasticsearch.enabled`, not `oap.storageType`, so `--set oap.storageType=banyandb` on its own
still deploys ECK and an Elasticsearch cluster nobody uses. Turn it off explicitly:

```yaml
elasticsearch:
  enabled: false
  # Only read when oap.storageType is elasticsearch — i.e. an external cluster.
  config:
    host: elasticsearch-es-http
    port:
      http: 9200
```

## Required values

Three values have no default and must be set on every install (`ui.image.tag` only while the UI is
deployed — `ui.enabled` defaults to `true`):

| Value | Example |
|---|---|
| `oap.image.tag` | `11.0.0` |
| `oap.storageType` | `elasticsearch`, `postgresql`, `banyandb` |
| `ui.image.tag` | `horizon-1.0.0` |

Two more are required only when you switch a component on: `banyandb.image.tag` (e.g. `0.11.0`)
with `banyandb.enabled=true`, or rendering fails with `banyandb.image.tag is required`, and
`satellite.image.tag` with `satellite.enabled=true`.

## Next

- [Quick Start](../install/quick-start.md)
- [Where to Get the Chart](../install/chart-sources.md)
- [Version Compatibility](version-compatibility.md)
- [Elasticsearch](../storage/elasticsearch.md) · [BanyanDB](../storage/banyandb.md)
