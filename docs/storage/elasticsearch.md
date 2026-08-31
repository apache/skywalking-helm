# Elasticsearch

How to run SkyWalking OAP on Elasticsearch with this chart — either the ECK-managed cluster the chart
ships (`elasticsearch.enabled: true`, the default) or an Elasticsearch cluster you already run.

| | Embedded (default) | External |
|---|---|---|
| `elasticsearch.enabled` | `true` | `false` |
| Deploys | ECK operator + an `Elasticsearch` custom resource | nothing |
| CRD pre-install | **required** | not needed |
| Connection settings | computed from the release name | `elasticsearch.config.*` |
| Credentials | auto-generated `elastic` user secret | `elasticsearch.config.user` / `.password` |

Both modes need the chart's three required values, with `oap.storageType` set to `elasticsearch`:

```shell
--set oap.image.tag=11.0.0 --set oap.storageType=elasticsearch --set ui.image.tag=horizon-1.0.0
```

## Embedded ECK cluster

Elasticsearch is deployed through [ECK (Elastic Cloud on Kubernetes)](https://github.com/elastic/cloud-on-k8s).
Two subchart dependencies in `chart/skywalking/Chart.yaml` are gated on `elasticsearch.enabled`:

| Subchart | Version | Role |
|---|---|---|
| `eck-operator` | 3.3.1 | the ECK controller that turns the custom resource into pods |
| `eck-elasticsearch` (alias `elasticsearch`) | 0.18.1 | renders the `Elasticsearch` custom resource |

The default Elasticsearch version is `8.18.8` (`elasticsearch.version`).

### Install the CRDs first

The chart creates an `elasticsearch.k8s.elastic.co/v1` `Elasticsearch` object, so the ECK CRDs must
already exist when `helm install` runs. Install them once per cluster as their own release, at the
version pinned for `eck-operator` in `chart/skywalking/Chart.yaml`:

```shell
helm install eck-crds eck-operator-crds \
  --repo https://helm.elastic.co --version 3.3.1 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" --create-namespace
```

Then install SkyWalking with `--set eck-operator.installCRDs=false` so the bundled operator does not
try to create the same CRDs a second time:

```shell
helm install skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

CI installs the same CRD release from a checkout instead, unpacking `eck-operator-crds` out of the
vendored `chart/skywalking/charts/eck-operator-3.3.1.tgz` after `helm dep up` — see
`test/e2e/e2e-oap11-elasticsearch.yaml`.

### What the chart wires up

The Elasticsearch resource is named `{release}-elasticsearch` (override with
`elasticsearch.fullnameOverride`). ECK derives the rest of the names from it:

| Object | Name (release `skywalking`) |
|---|---|
| `Elasticsearch` custom resource | `skywalking-elasticsearch` |
| HTTP service | `skywalking-elasticsearch-es-http`, port `9200` |
| Auto-generated auth secret | `skywalking-elasticsearch-es-elastic-user`, key `elastic` |

Both the OAP Deployment and the OAP init Job get the same storage env block, with the password read
straight from the ECK secret — you never set an Elasticsearch password yourself in this mode:

```yaml
- name: SW_STORAGE
  value: elasticsearch
- name: SW_STORAGE_ES_CLUSTER_NODES
  value: "skywalking-elasticsearch-es-http:9200"
- name: SW_ES_USER
  value: "elastic"
- name: SW_ES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: skywalking-elasticsearch-es-elastic-user
      key: elastic
```

To read that password yourself (for `curl`, Kibana, or a support dump):

```shell
kubectl -n "${SKYWALKING_RELEASE_NAMESPACE}" get secret skywalking-elasticsearch-es-elastic-user \
  -o go-template='{{.data.elastic | base64decode}}'
```

The OAP Deployment and the init Job also both get a `wait-for-elasticsearch` init container
(`busybox:1.30`, from `initContainer.image` / `initContainer.tag`) that TCP-probes
`{release}-elasticsearch-es-http:9200` up to 60 times, 5 seconds apart, before OAP starts. If ES
never becomes reachable the init container exits 1 — the Deployment pod sits in
`Init:CrashLoopBackOff` and retries, while the init Job's pod fails and the Job creates another.

### HTTP TLS is disabled by default

`values.yaml` ships:

```yaml
elasticsearch:
  http:
    tls:
      selfSignedCertificate:
        disabled: true
```

so OAP reaches Elasticsearch over plain HTTP inside the cluster and does not need to trust the ECK
self-signed CA. To re-enable TLS, remove the `tls` section (or set `disabled: false`) **and**
configure OAP to trust the certificate — the chart does not do that part for you. Anything extra OAP
needs can be passed with `--set oap.env.<NAME>=<VALUE>`, for example
`--set oap.env.SW_STORAGE_ES_HTTP_PROTOCOL=https`.

`elasticsearch.http` is passed through verbatim to the custom resource, so it also carries service
settings such as `http.service.spec.type: LoadBalancer`. See
[Accessing Elastic services](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-accessing-elastic-services.html).

### Cluster topology (`nodeSets`)

`elasticsearch.nodeSets[]` is passed straight through to the ECK
[node sets](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-node-configuration.html).
Each entry creates a group of Elasticsearch nodes.

| Parameter | Default | Notes |
|---|---|---|
| `nodeSets[].name` | `default` | node set name |
| `nodeSets[].count` | `3` | nodes in this set |
| `nodeSets[].config` | `node.store.allow_mmap: false` | Elasticsearch settings (`node.roles`, watermarks, …) |
| `nodeSets[].volumeClaimTemplates` | not set | commented example in `values.yaml`; ECK applies its own default claim when omitted |
| `nodeSets[].podTemplate` | resources `100m` CPU / `2Gi` memory (request), `2Gi` memory (limit) | a normal Pod template under `podTemplate.spec` |

`nodeSets` is a list, so `--set` replaces the whole thing. Use a values file:

```yaml
elasticsearch:
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 30Gi
        storageClassName: standard
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              cpu: 1
              memory: 4Gi
            limits:
              memory: 4Gi
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms2g -Xmx2g"
```

For production, `values.yaml` recommends raising the kernel setting `vm.max_map_count` to `262144`
with a privileged init container and leaving `node.store.allow_mmap` unset instead of `false` — see
[Virtual memory](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html).
`test/e2e/values.yaml` shows the opposite end of the scale: a single node with relaxed disk
watermarks, sized for kind.

### Other passthrough parameters

| Parameter | Default | Description |
|---|---|---|
| `elasticsearch.version` | `8.18.8` | Elasticsearch version |
| `elasticsearch.fullnameOverride` | `""` | rename the resource; the service becomes `{name}-es-http` |
| `elasticsearch.labels` / `.annotations` | `{}` | applied to the `Elasticsearch` resource |
| `elasticsearch.secureSettings` | `[]` | [secure settings](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-es-secure-settings.html) from Kubernetes secrets |
| `elasticsearch.updateStrategy` | `{}` | [change budget](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-update-strategy.html) for rolling changes |
| `elasticsearch.volumeClaimDeletePolicy` | `""` | `DeleteOnScaledownOnly` or `DeleteOnScaledownAndClusterDeletion` |
| `elasticsearch.ingress.enabled` | `false` | expose Elasticsearch itself through an Ingress |

## Use an existing Elasticsearch

Set `elasticsearch.enabled: false` and point `elasticsearch.config` at your cluster. This skips both
the ECK operator and the custom resource, so **no CRD pre-install is needed**.

```yaml
elasticsearch:
  enabled: false
  config:
    host: elasticsearch-es-http
    port:
      http: 9200
    user: "xxx"         # [optional]
    password: "xxx"     # [optional]
```

| Parameter | Default | Description |
|---|---|---|
| `elasticsearch.config.host` | `elasticsearch` | hostname reachable from the OAP pods |
| `elasticsearch.config.port.http` | `9200` | HTTP port |
| `elasticsearch.config.user` | `""` | optional; sets `SW_ES_USER` |
| `elasticsearch.config.password` | `""` | optional; sets `SW_ES_PASSWORD` |

`host` and `port.http` feed both `SW_STORAGE_ES_CLUSTER_NODES` and the `wait-for-elasticsearch` init
container probe. `user` and `password` are only emitted when non-empty, and they are rendered as
literal env values in the OAP pod spec. Leave both empty and put `SW_ES_USER` / `SW_ES_PASSWORD` in a
Secret referenced by `oap.envFromSecret` instead — see
[Storage credentials from a Secret](../operate/oap-configuration.md#storage-credentials-from-a-secret).
For a TLS-fronted cluster add `--set oap.env.SW_STORAGE_ES_HTTP_PROTOCOL=https` (OAP defaults to
`http`).

`chart/skywalking/values-my-es.yaml` is the ready-made example. It already carries the three required
values, so nothing else has to be passed:

```shell
helm dep up chart/skywalking   # charts/ is gitignored — vendor the dependencies first
helm install "${SKYWALKING_RELEASE_NAME}" chart/skywalking \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -f chart/skywalking/values-my-es.yaml
```

## Related

- [Pick a Storage Backend](choose-a-backend.md) — how Elasticsearch compares with BanyanDB and PostgreSQL
- [The OAP Init Job](../operate/oap-init-job.md) — what creates the Elasticsearch indices
- [Install and Startup Failures](../troubleshooting/install-and-startup.md) — CRD and `wait-for-elasticsearch` errors
- [skywalking Chart Values](../reference/skywalking-chart-values.md) — full parameter list
- [OAP Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/) — every `SW_STORAGE_ES_*` variable
