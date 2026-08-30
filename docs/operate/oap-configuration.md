# Configure OAP

How to change OAP backend behaviour from the chart: environment variables (`oap.env`), overridden
configuration files under `/skywalking/config` (`oap.config`), and runtime dynamic configuration
backed by a ConfigMap (`oap.dynamicConfig`).

## Three levers

| Value | What it changes | Applies to | Takes effect |
|---|---|---|---|
| `oap.env` | Environment variables on the OAP container | OAP Deployment **and** the OAP init Job | On pod restart (Helm rolls the Deployment because the pod spec changed) |
| `oap.config` | Files dropped into `/skywalking/config` | OAP Deployment **and** the OAP init Job | On pod restart — see the caveat below, a config-only change does **not** roll the Deployment |
| `oap.dynamicConfig` | Runtime rules OAP re-reads from a ConfigMap | OAP Deployment only | Within `oap.dynamicConfig.period` seconds, no restart |

Environment variables win over the shipped configuration files: OAP's `application.yml` resolves
almost every setting as `${SW_SOMETHING:default}`, so setting `SW_SOMETHING` overrides the default
baked into the image. That only holds while the placeholder survives — if you replace a file through
`oap.config` and write a literal where the shipped file had `${SW_SOMETHING:...}`, the literal wins
and the variable is ignored.

## Environment variables (`oap.env`)

`oap.env` is a plain map of name to value. Every entry is appended to the container `env` list (the
chart quotes the value, so numbers and booleans are safe to write unquoted).

```shell
helm upgrade --install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set oap.env.SW_ENVOY_METRIC_ALS_HTTP_ANALYSIS=k8s-mesh \
  --set oap.env.SW_ENVOY_METRIC_ALS_TCP_ANALYSIS=k8s-mesh
```

Or in a values file, which is easier once you have more than one or a value contains commas:

```yaml
oap:
  env:
    SW_ENVOY_METRIC_ALS_HTTP_ANALYSIS: k8s-mesh
    SW_ENVOY_METRIC_ALS_TCP_ANALYSIS: k8s-mesh
    K8S_SERVICE_NAME_RULE: 'e2e::${service.metadata.name}'
    SW_CORE_RECORD_DATA_TTL: 3
```

The full list of variables OAP understands is upstream:
[Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/).

### Variables the chart already manages

Do not set these through `oap.env` — `oap.env` is rendered *after* them, producing a duplicate entry
in the same `env` list instead of a clean override. Use the dedicated value instead.

| Variable(s) | Set by the chart from | Use this instead |
|---|---|---|
| `JAVA_OPTS` | `oap.javaOpts` plus `-Dmode=no-init` (`-Dmode=init` in the init Job) | `oap.javaOpts` (default `-Xmx2g -Xms2g`) |
| `SW_STORAGE`, `SW_STORAGE_ES_CLUSTER_NODES`, `SW_ES_USER`, `SW_ES_PASSWORD`, `SW_JDBC_URL`, `SW_DATA_SOURCE_USER`, `SW_DATA_SOURCE_PASSWORD`, `SW_STORAGE_BANYANDB_TARGETS`, `SW_STORAGE_BANYANDB_USER`, `SW_STORAGE_BANYANDB_PASSWORD` | `oap.storageType` and the storage backend's own values | [Pick a Storage Backend](../storage/choose-a-backend.md) |
| `SW_CLUSTER`, `SW_CLUSTER_K8S_NAMESPACE`, `SW_CLUSTER_K8S_LABEL` | Fixed to `kubernetes` plus the release namespace and label selector | Nothing — the chart always runs OAP in Kubernetes cluster mode |
| `SW_RECEIVER_ZIPKIN`, `SW_RECEIVER_ZIPKIN_REST_PORT`, `SW_QUERY_ZIPKIN`, `SW_QUERY_ZIPKIN_REST_PORT` | Rendered only when `oap.ports.zipkin-receiver` / `oap.ports.zipkin-query` are set | `oap.ports` |
| `SW_CONFIGURATION`, `SW_CONFIG_CONFIGMAP_PERIOD` | Rendered when `oap.dynamicConfig.enabled` is `true` | `oap.dynamicConfig` |
| `SKYWALKING_COLLECTOR_UID` | The pod UID, via the downward API | Nothing |

`JAVA_OPTS` is the one that bites: a second entry can shadow the chart's `-Dmode=no-init`, which is
what makes the Deployment leave schema creation to the init Job. Put JVM flags in `oap.javaOpts`.

`oap.env` is also applied to the one-shot OAP init Job, so schema-affecting variables (storage TTL,
index settings) reach the process that creates the schema. See [The OAP Init Job](oap-init-job.md).

## Configuration file overrides (`oap.config`)

`oap.config` drops arbitrary files into `/skywalking/config` inside the OAP container — the image's
own config directory. Every top-level key becomes a file name; a **nested map becomes a
subdirectory**, up to three levels deep.

```yaml
oap:
  config:
    log4j2.xml: |
      <Configuration status="DEBUG">
        <!-- ... -->
      </Configuration>
    metadata-service-mapping.yaml: |
      serviceName: e2e::${LABELS."service.istio.io/canonical-name"}
      serviceInstanceName: ${NAME}
    oal:
      core.oal: |
        service_resp_time = from(Service.latency).longAvg();
        service_sla = from(Service.*).percent(status == true);
        service_cpm = from(Service.*).cpm();
    otel-rules:
      k8s:
        k8s-cluster.yaml: |
          # three levels also work
```

That renders to these mounts in the OAP container:

| `oap.config` path | Mounted at |
|---|---|
| `log4j2.xml` | `/skywalking/config/log4j2.xml` |
| `metadata-service-mapping.yaml` | `/skywalking/config/metadata-service-mapping.yaml` |
| `oal` → `core.oal` | `/skywalking/config/oal/core.oal` |
| `otel-rules` → `k8s` → `k8s-cluster.yaml` | `/skywalking/config/otel-rules/k8s/k8s-cluster.yaml` |

### How it works

The chart flattens the nested map into a single ConfigMap named `{fullname}-oap-cm-override` (for a
release `skywalking`, `skywalking-skywalking-helm-oap-cm-override`), joining path segments with `-`:
`oal` → `core.oal` becomes the ConfigMap key `oal-core.oal`. Each key is then mounted back at its
real path with `subPath`, so only that one file is placed and the rest of the image's
`/skywalking/config` directory stays intact.

```shell
kubectl get cm -n skywalking -l component=oap
kubectl exec -n skywalking deploy/skywalking-skywalking-helm-oap -- ls /skywalking/config/oal
```

Two consequences worth knowing:

- **A config-only change does not restart OAP.** The Deployment's pod template does not embed a
  checksum of this ConfigMap, and `subPath` mounts do not track ConfigMap updates. After a
  `helm upgrade` that only touches `oap.config`, roll the pods yourself:
  ```shell
  kubectl rollout restart -n skywalking deploy/skywalking-skywalking-helm-oap
  ```
  (The init Job *is* re-created, because its name hashes the chart values.)
- **Avoid `-` collisions in the flattened key space.** A top-level key literally named `oal-core.oal`
  and a nested `oal` → `core.oal` produce the same ConfigMap key.

Files most commonly overridden here: `log4j2.xml` (log level and appenders), `oal/*.oal`
([OAL scripts](https://skywalking.apache.org/docs/main/latest/en/concepts-and-designs/oal/)) and
`metadata-service-mapping.yaml` (Kubernetes-to-service naming for the Envoy/mesh receivers).

Secrets — TLS material, keystores — should go through `oap.secretMounts` rather than `oap.config`,
which is a plain ConfigMap.

## Dynamic configuration (`oap.dynamicConfig`)

Dynamic configuration is OAP's runtime-rule mechanism: alarm rules, sampling policies, thresholds
that you want to change without restarting the backend. Setting `oap.dynamicConfig.enabled=true`
wires OAP to its `k8s-configmap` configuration provider.

```yaml
oap:
  dynamicConfig:
    enabled: true
    period: 60
    config:
      agent-analyzer.default.slowDBAccessThreshold: default:200,mongodb:50
      alarm.default.alarm-settings: |
        rules:
          service_resp_time_rule:
            metrics-name: service_resp_time
            op: ">"
            threshold: 1000
            period: 10
            count: 3
            silence-period: 5
            message: Response time of service {name} is more than 1000ms in 3 minutes of last 10 minutes.
```

What the chart does when `enabled` is `true`:

| | |
|---|---|
| ConfigMap | Creates one named exactly `skywalking-dynamic-config`, with `data` taken verbatim from `oap.dynamicConfig.config` and labels `app`/`release`/`component` |
| Env | Sets `SW_CONFIGURATION=k8s-configmap` and `SW_CONFIG_CONFIGMAP_PERIOD` to `oap.dynamicConfig.period` (seconds, default `60`) on the OAP Deployment |
| Discovery | OAP finds the ConfigMap in `SW_CLUSTER_K8S_NAMESPACE` (the release namespace) using the label selector `SW_CLUSTER_K8S_LABEL`, which the chart sets to `app=<release>,release=<release>,component=oap` — the same labels it puts on the ConfigMap |
| RBAC | The chart's Role already grants `get`/`watch`/`list` on `configmaps` when `serviceAccounts.oap.create` is `true` |

Keys are `<module>.<provider>.<config-name>`; values may be a scalar or a multi-line block. The
catalogue of supported keys is upstream:
[Dynamic Configuration](https://skywalking.apache.org/docs/main/latest/en/setup/backend/dynamic-config/),
and the provider the chart wires up is
[Dynamic Configuration ConfigMap](https://skywalking.apache.org/docs/main/latest/en/setup/backend/dynamic-config-configmap/).

Things to watch:

- **The default `config` is `{}`.** Turning `enabled` on by itself creates an empty ConfigMap and
  changes no behaviour — OAP keeps using its static defaults until you add keys.
- **The ConfigMap name is fixed**, not release-prefixed. Two SkyWalking releases in the same
  namespace would fight over `skywalking-dynamic-config`; give them separate namespaces.
- **Helm owns the content.** Editing the ConfigMap with `kubectl edit` works until the next
  `helm upgrade`, which resets it to `oap.dynamicConfig.config`. Keep the values file as the source
  of truth.
- **The init Job does not get these variables** — dynamic configuration applies to the running OAP
  Deployment only.

Verify it took:

```shell
kubectl get cm skywalking-dynamic-config -n skywalking -o yaml
kubectl logs -n skywalking deploy/skywalking-skywalking-helm-oap | grep -i configmap
```

## Related

- [The OAP Init Job](oap-init-job.md) — which changes re-run schema creation
- [Scaling and the OAP Cluster](scaling.md)
- [OAP Endpoints for Agents](../expose/oap-endpoints.md) — `oap.ports` and the Service
- [skywalking Chart Values](../reference/skywalking-chart-values.md) — every `oap.*` value
- [OAP Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/)
