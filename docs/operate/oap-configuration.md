# Configure OAP

OAP is configured three ways, the same three the UI offers: environment variables (`oap.env`,
`oap.extraEnv`), a Secret exposed as environment variables (`oap.envFromSecret`), and files dropped
into `/skywalking/config` (`oap.config`). On top of those sits `oap.dynamicConfig`, OAP's own
runtime-rule mechanism.

Prefer the first two. Reach for `oap.config` only for the files env cannot express — see
[why OAP still needs a file](#why-oap-still-needs-a-file-where-horizon-does-not).

## The levers

| Value | What it changes | Applies to | Takes effect |
|---|---|---|---|
| `oap.env` | Environment variables, as a plain map | OAP Deployment **and** the OAP init Job | On restart — `helm upgrade` rolls the Deployment, and re-creates the init Job (its name hashes the values) |
| `oap.extraEnv` | Environment variables, as a **list** — entries may carry `valueFrom` | OAP Deployment **and** the OAP init Job | Same |
| `oap.envFromSecret` | Every key of an existing Secret, as environment variables | OAP Deployment **and** the OAP init Job | Same — but editing the Secret's *contents* changes no pod field, so nothing rolls; restart the pods yourself |
| `oap.config` | Files placed into `/skywalking/config` | OAP Deployment **and** the OAP init Job | On restart — but editing a file's *contents* changes no pod field, so nothing rolls; see the caveat below |
| `oap.dynamicConfig` | Runtime rules OAP re-reads from a ConfigMap | OAP Deployment only | Within `oap.dynamicConfig.period` seconds, no restart |

Environment variables win over the shipped configuration files: OAP's `application.yml` resolves
almost every setting as `${SW_SOMETHING:default}`, so setting `SW_SOMETHING` overrides the default
baked into the image. That only holds while the placeholder survives — if you replace a file through
`oap.config` and write a literal where the shipped file had `${SW_SOMETHING:...}`, the literal wins
and the variable is ignored.

## Why OAP still needs a file where Horizon does not

Horizon's image ships a `/app/horizon.yaml` in which *every* field is a `${HORIZON_*:default}`
token, so the chart mounts nothing by default and sets plain env vars instead — see
[Configure Horizon](../ui/configure.md).

OAP is only half that. `application.yml` is tokenized the same way, so every setting in it is
reachable from the environment, and so is `bydb.yml` — the BanyanDB group file, every shard/TTL
knob in it a `${SW_STORAGE_BANYANDB_*}`. The logging and rule documents are not: OAP reads those as
**real files**, and no variable can carry them.

| File in `/skywalking/config` | Why env cannot reach it |
|---|---|
| `log4j2.xml` | Levels and appenders are literals. The image's copy has no `${...}` at all — the Dockerfile deletes the tarball's file (which carries `${sys:oap.logDir}`, a JVM system property, not an env var) and ships a console-only one |
| `oal/*.oal` | OAL source OAP compiles at boot — a script, not a setting |
| `otel-rules/*`, `meter-analyzer-config/*`, `log-mal-rules/*`, `lal/*`, `metadata-service-mapping.yaml` | MAL/LAL rule documents, read whole |

So: environment variables for anything in `application.yml` or `bydb.yml`, `oap.config` for the
logging and rule files.

## Environment variables

### `oap.env` — a map

A plain map of name to value. Every entry is appended to the container `env` list (the chart quotes
the value, so numbers and booleans are safe to write unquoted). It cannot express `valueFrom`.

```yaml
oap:
  env:
    SW_ENVOY_METRIC_ALS_HTTP_ANALYSIS: k8s-mesh
    SW_ENVOY_METRIC_ALS_TCP_ANALYSIS: k8s-mesh
    K8S_SERVICE_NAME_RULE: 'e2e::${service.metadata.name}'
    SW_CORE_RECORD_DATA_TTL: 3
```

`--set oap.env.SW_CORE_RECORD_DATA_TTL=3` works as well, but a values file is easier once you have
more than one, or a value contains commas.

The full list of variables OAP understands is upstream:
[Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/).

### `oap.extraEnv` — a list, for `valueFrom`

A list of raw Kubernetes `EnvVar` entries, rendered verbatim after `oap.env`. Use it where a map
cannot reach — anything needing `valueFrom`: one value out of a Secret (`secretKeyRef`) or a
ConfigMap (`configMapKeyRef`), a pod field (`fieldRef`), a resource limit (`resourceFieldRef`).

```yaml
oap:
  extraEnv:
    - name: SW_DATA_SOURCE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: oap-postgres
          key: password
```

### `oap.envFromSecret` — a whole Secret

The name of a **pre-existing** Secret in the release namespace; the chart turns it into an
`envFrom.secretRef` on both OAP containers, so every key becomes a variable. The chart does not
create the Secret, and does not mark the reference optional — if it is missing, the pods sit in
`CreateContainerConfigError`.

```yaml
oap:
  envFromSecret: oap-storage
```

### Precedence

The rendered `env` list is, in order: the variables the chart computes, then `oap.env`, then
`oap.extraEnv`. Kubernetes resolves `envFrom` first and lets `env` replace it, and within `env` a
later entry with the same name replaces an earlier one. So:

- **`oap.extraEnv` can override anything**, including the storage block the chart computes. Both
  entries stay visible in the pod spec; the later one is what the process sees.
- **`oap.envFromSecret` can only fill names the chart leaves unset.** A key that collides with a
  variable the chart already writes as `env` is silently ignored.

### Variables the chart already manages

| Variable(s) | Set by the chart from | Use this instead |
|---|---|---|
| `JAVA_OPTS` | `oap.javaOpts` plus `-Dmode=no-init` (`-Dmode=init` in the init Job) | `oap.javaOpts` (default `-Xmx2g -Xms2g`) |
| `SW_STORAGE`, `SW_STORAGE_ES_CLUSTER_NODES`, `SW_ES_USER`, `SW_ES_PASSWORD`, `SW_JDBC_URL`, `SW_DATA_SOURCE_USER`, `SW_DATA_SOURCE_PASSWORD`, `SW_STORAGE_BANYANDB_TARGETS`, `SW_STORAGE_BANYANDB_USER`, `SW_STORAGE_BANYANDB_PASSWORD` | `oap.storageType` and the storage backend's own values | [Pick a Storage Backend](../storage/choose-a-backend.md); for the credentials, [Storage credentials from a Secret](#storage-credentials-from-a-secret) |
| `SW_CLUSTER`, `SW_CLUSTER_K8S_NAMESPACE`, `SW_CLUSTER_K8S_LABEL` | Fixed to `kubernetes` plus the release namespace and label selector | Nothing — the chart always runs OAP in Kubernetes cluster mode |
| `SW_RECEIVER_ZIPKIN`, `SW_RECEIVER_ZIPKIN_REST_PORT`, `SW_QUERY_ZIPKIN`, `SW_QUERY_ZIPKIN_REST_PORT` | Rendered only when `oap.ports.zipkin-receiver` / `oap.ports.zipkin-query` are set | `oap.ports` |
| `SW_CONFIGURATION`, `SW_CONFIG_CONFIGMAP_PERIOD` | Rendered when `oap.dynamicConfig.enabled` is `true` | `oap.dynamicConfig` |
| `SKYWALKING_COLLECTOR_UID` | The pod UID, via the downward API | Nothing |

`JAVA_OPTS` is the one that bites: a second entry replaces the chart's, dropping `-Dmode=no-init` —
which is what makes the Deployment leave schema creation to the init Job. Put JVM flags in
`oap.javaOpts`.

All three env mechanisms also apply to the one-shot OAP init Job, so schema-affecting variables
(storage credentials, TTL, index settings) reach the process that creates the schema. See
[The OAP Init Job](oap-init-job.md).

## Storage credentials from a Secret

The storage block is computed from values, which means a password written in `values.yaml` ends up
as a literal in the OAP pod spec. Keep it in a Secret instead. (Embedded Elasticsearch,
`elasticsearch.enabled=true`, is already safe: the chart reads `SW_ES_PASSWORD` from the
ECK-generated secret with a `secretKeyRef`. Everything below is for the external backends.)

### External Elasticsearch — `oap.envFromSecret`

`SW_ES_USER` / `SW_ES_PASSWORD` are only emitted for an external cluster when
`elasticsearch.config.user` / `.password` are non-empty. Leave both empty and the names are free for
a Secret to fill:

```shell
kubectl create secret generic oap-storage -n skywalking \
  --from-literal=SW_ES_USER=skywalking \
  --from-literal=SW_ES_PASSWORD='<the password>'
```

```yaml
# oap-storage.yaml
oap:
  image:
    tag: 11.0.0
  storageType: elasticsearch
  envFromSecret: oap-storage
ui:
  image:
    tag: horizon-1.0.0
elasticsearch:
  enabled: false
  config:
    host: es.internal
    port:
      http: 9200
```

Confirm the render before installing — the Deployment *and* the Job must both carry the
`secretRef`, or schema creation authenticates with nothing:

```shell
helm template sw chart/skywalking -f oap-storage.yaml \
  -s templates/oap-deployment.yaml -s templates/oap-init.job.yaml \
  | grep -E '^kind:|SW_ES|SW_STORAGE$|secretRef|name: oap-storage'
```

```text
kind: Deployment
        - name: SW_STORAGE
        - secretRef:
            name: oap-storage
kind: Job
        - name: SW_STORAGE
        - secretRef:
            name: oap-storage
```

No `SW_ES_PASSWORD` appears in either pod spec: the only copy lives in the Secret.

### PostgreSQL — `oap.extraEnv`

PostgreSQL is different, because the chart writes `SW_DATA_SOURCE_PASSWORD` **unconditionally** from
`postgresql.auth.password`. An `env` entry beats `envFrom`, so a key of that name in
`oap.envFromSecret` would be ignored. Override it with `oap.extraEnv`, which renders after the
storage block:

```yaml
# oap-postgres.yaml
oap:
  image:
    tag: 11.0.0
  storageType: postgresql
  extraEnv:
    - name: SW_DATA_SOURCE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: oap-postgres
          key: password
ui:
  image:
    tag: horizon-1.0.0
elasticsearch:
  enabled: false
postgresql:
  enabled: false
  config:
    host: pg.internal
  auth:
    password: ""   # the shadowed literal is still in the pod spec — keep it empty
```

```shell
helm template sw chart/skywalking -f oap-postgres.yaml \
  -s templates/oap-deployment.yaml | grep -A4 SW_DATA_SOURCE_PASSWORD
```

```text
        - name: SW_DATA_SOURCE_PASSWORD
          value: ""
        - name: SW_DATA_SOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: oap-postgres
```

Two entries, and the second wins. Swap `-s templates/oap-init.job.yaml` into that command to see
the init Job carrying the same pair.

BanyanDB behaves like Elasticsearch: the chart writes `SW_STORAGE_BANYANDB_USER` /
`SW_STORAGE_BANYANDB_PASSWORD` only when `banyandb.auth.enabled` is `true` **and**
`banyandb.auth.users` is non-empty. `banyandb.auth.enabled` defaults to `false` — note that
`banyandb.auth.users` does *not* default to empty, it carries an `admin`/`banyandb` entry — so
against an external cluster leave `auth.enabled` off and `oap.envFromSecret` fills both names
cleanly.

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

That renders to these mounts, in the OAP container **and** in the init Job:

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

- **Editing a file's contents does not restart OAP.** The Deployment's pod template does not embed
  a checksum of this ConfigMap, and `subPath` mounts do not track ConfigMap updates. (Adding or
  removing a *path* does roll it — that changes the mount list.) After a `helm upgrade` that only
  rewrites a file already in `oap.config`, roll the pods yourself:
  ```shell
  kubectl rollout restart -n skywalking deploy/skywalking-skywalking-helm-oap
  ```
  (The init Job *is* re-created, because its name hashes the chart values.)
- **Avoid `-` collisions in the flattened key space.** A top-level key literally named `oal-core.oal`
  and a nested `oal` → `core.oal` produce the same ConfigMap key.

Secrets do not belong here — it is a plain ConfigMap. Credentials go through `oap.envFromSecret` or
`oap.extraEnv`; TLS material and keystores, which have to be files, go through `oap.secretMounts`.

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
- [Configure Horizon](../ui/configure.md) — the same three mechanisms on the UI side
- [Scaling and the OAP Cluster](scaling.md)
- [OAP Endpoints for Agents](../expose/oap-endpoints.md) — `oap.ports` and the Service
- [skywalking Chart Values](../reference/skywalking-chart-values.md) — every `oap.*` value
- [OAP Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/)
