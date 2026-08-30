# skywalking Chart Values

The values the `skywalking` chart defines itself, plus the `elasticsearch.*` keys its
`values.yaml` ships. Set them with `--set key=value` or a values file (`-f my-values.yaml`).

This is not the full accepted surface. *Most* keys under a subchart alias — `banyandb.*`,
`postgresql.*`, `eck-operator.*`, and the `elasticsearch.*` keys not listed below — are passed
straight through to that subchart, and its own values file is the reference. See
[BanyanDB](../storage/banyandb.md), [PostgreSQL](../storage/postgresql.md) and
[Elasticsearch](../storage/elasticsearch.md).

The exception is the storage connection block. `elasticsearch.config.*`, `banyandb.config.*` and
`postgresql.config.host` are this chart's own keys — no subchart defines them; `_helpers.tpl` reads
them to build the OAP storage env and the `wait-for-storage` init container. Looking for them in a
subchart's values file will not find them, so they are tabled below alongside the chart's own values.
`helm show values chart/skywalking` prints the whole merged default set.

Three values have no default and must be set on every install:

| name | description | example |
|---|---|---|
| `oap.image.tag` | OAP image tag | `11.0.0` |
| `oap.storageType` | storage backend | `elasticsearch`, `postgresql`, `banyandb` |
| `ui.image.tag` | Horizon UI image tag | `horizon-1.0.0` |

Two more have no default but are required only when the component that consumes them is enabled.
Both fail the render rather than defaulting:

| name | required when | example |
|---|---|---|
| `banyandb.image.tag` | `banyandb.enabled=true` — otherwise the subchart is not rendered at all | `0.11.0` |
| `satellite.image.tag` | `satellite.enabled=true` (`false` by default) | `v1.3.0` |

The following table lists the configurable parameters of the Skywalking chart and their default values.

| Parameter                              | Description                                                                                                                                                                                                                                                                                                                | Default                                                                                                                  |
|----------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `nameOverride`                         | Override the chart name used in resource names                                                                                                                                                                                                                                                                             | `""`                                                                                                                     |
| `fullnameOverride`                     | Override the full resource-name prefix outright (the e2e tests set this to `skywalking`)                                                                                                                                                                                                                                    | `""`                                                                                                                     |
| `initContainer.image`                  | Image for the chart's `wait-for-storage` init container                                                                                                                                                                                                                                                                    | `busybox`                                                                                                                |
| `initContainer.tag`                    | Tag for the `wait-for-storage` init container image                                                                                                                                                                                                                                                                        | `1.30`                                                                                                                   |
| `serviceAccounts.oap.create`           | Create of the OAP service account                                                                                                                                                                                                                                                                                          | `true`                                                                                                                   |
| `serviceAccounts.oap.name`             | Name of a pre-existing OAP service account, used when `serviceAccounts.oap.create` is `false`                                                                                                                                                                                                                               | `""`                                                                                                                     |
| `imagePullSecrets`                     | Image pull secrets                                                                                                                                                                                                                                                                                                         | `[]`                                                                                                                     |
| `oap.name`                             | OAP deployment name                                                                                                                                                                                                                                                                                                        | `oap`                                                                                                                    |
| `oap.dynamicConfig.enabled`            | Enable oap dynamic configuration through k8s configmap                                                                                                                                                                                                                                                                     | `false`                                                                                                                  |
| `oap.dynamicConfig.period`             | Sync period in seconds                                                                                                                                                                                                                                                                                                     | `60`                                                                                                                     |
| `oap.dynamicConfig.config`             | Oap dynamic configuration [documentation](https://github.com/apache/skywalking/blob/master/docs/en/setup/backend/dynamic-config.md)                                                                                                                                                                                        | `{}`                                                                                                                     |
| `oap.image.repository`                 | OAP container image name                                                                                                                                                                                                                                                                                                   | `skywalking.docker.scarf.sh/apache/skywalking-oap-server`                                                                |
| `oap.image.tag`                        | OAP container image tag. Required on every install -- no default                                                                                                                                                                                                                                                           | `null`                                                                                                                  |
| `oap.image.pullPolicy`                 | OAP container image pull policy                                                                                                                                                                                                                                                                                            | `IfNotPresent`                                                                                                           |
| `oap.ports.grpc`                       | OAP grpc port for tracing or metric                                                                                                                                                                                                                                                                                        | `11800`                                                                                                                  |
| `oap.ports.rest`                       | OAP http port for the GraphQL query protocol (used by the UI and by `swctl`)                                                                                                                                                                                                                                               | `12800`                                                                                                                  |
| `oap.ports.admin`                      | OAP admin REST port (admin-server, status, inspect, ui-management, dsl-debugging, runtime-rule). Introduced in OAP 11, which enables all of them by default and serves `/status/*` and `/debugging/*` here exclusively. Set to `null` on any OAP 10.x release, where 17128 is the AI-pipeline URI-recognition server instead | `17128`                                                                                                                  |
| `oap.ports.zipkin-receiver`            | OAP http port for Zipkin receiver(not exposed by default)                                                                                                                                                                                                                                                                  | not set (commented out in `values.yaml`) |
| `oap.ports.zipkin-query`               | OAP http port for querying Zipkin traces and UI(not exposed by default)                                                                                                                                                                                                                                                    | not set (commented out in `values.yaml`) |
| `oap.ports.promql` / `logql` / `traceql` / `metrics` | Further OAP listeners, each commented out in `values.yaml`. Any key added under `oap.ports` becomes both a container port and a Service port, named after the key                                                                                                                                             | not set (commented out in `values.yaml`) |
| `oap.replicas`                         | OAP k8s deployment replicas                                                                                                                                                                                                                                                                                                | `2`                                                                                                                      |
| `oap.service.type`                     | OAP svc type                                                                                                                                                                                                                                                                                                               | `ClusterIP`                                                                                                              |
| `oap.service.annotations`              | OAP svc annotations                                                                                                                                                                                                                                                                                                        | `{}`                                                                                                                     |
| `oap.javaOpts`                         | Parameters to be added to the `JAVA_OPTS` environment variable for OAP                                                                                                                                                                                                                                                     | `-Xmx2g -Xms2g`                                                                                                          |
| `oap.antiAffinity`                     | OAP anti-affinity policy                                                                                                                                                                                                                                                                                                   | `soft`                                                                                                                   |
| `oap.nodeAffinity`                     | OAP node affinity policy                                                                                                                                                                                                                                                                                                   | `{}`                                                                                                                     |
| `oap.nodeSelector`                     | OAP labels for master pod assignment                                                                                                                                                                                                                                                                                       | `{}`                                                                                                                     |
| `oap.tolerations`                      | OAP tolerations                                                                                                                                                                                                                                                                                                            | `[]`                                                                                                                     |
| `oap.resources`                        | OAP node resources requests & limits                                                                                                                                                                                                                                                                                       | `{} - cpu limit must be an integer`                                                                                      |
| `oap.startupProbe`                     | Configuration fields for the [startupProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/). `values.yaml` ships `{}` and the template renders the fallback shown here; setting the value replaces it wholesale. The default budget (`failureThreshold` * `periodSeconds` = 300s) is large enough for OAP to wait in no-init mode while the OAP init Job creates the storage schema. | `tcpSocket.port: 12800` <br> `failureThreshold: 30` <br> `periodSeconds: 10`
| `oap.livenessProbe`                    | Configuration fields for the [livenessProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)                                                                                                                                                                        | `tcpSocket.port: 12800` <br> `initialDelaySeconds: 5` <br> `periodSeconds: 10`
| `oap.readinessProbe`                   | Configuration fields for the [readinessProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)                                                                                                                                                                       | `tcpSocket.port: 12800` <br> `initialDelaySeconds: 5` <br> `periodSeconds: 10`
| `oap.env`                              | OAP environment variables                                                                                                                                                                                                                                                                                                  | not set                                                                                                                  |
| `oap.podAnnotations`                   | Annotations applied to all OAP pods                                                                                                                                                                                                                                                                                        | not set (commented out in `values.yaml`)                                                                                 |
| `oap.config`                           | Extra files written into `/skywalking/config` (e.g. `log4j2.xml`, `oal/core.oal`), keyed by path                                                                                                                                                                                                                            | `{}`                                                                                                                     |
| `oap.secretMounts`                     | Secrets to mount into the OAP pod, each `{name, secretName, path}`                                                                                                                                                                                                                                                          | `[]`                                                                                                                     |
| `oap.securityContext`                  | Allows you to set the [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) for the pod                                                                                                                                                         | `{}` |
| `oap.sidecars`                         | Extra sidecar containers to run in the OAP pod (appended to the pod's `containers` list, rendered through `tpl`)                                                                                                                                                                                                            | `[]`                                                                                                                     |
| `ui.enabled`                           | Deploy the Horizon UI. Set `false` to skip the UI Deployment, Service, Ingress, ConfigMap, and PVC entirely (useful when an external UI talks to OAP directly)                                                                                                                                                             | `true`                                                                                                                   |
| `ui.name`                              | Web UI deployment name                                                                                                                                                                                                                                                                                                     | `ui`                                                                                                                     |
| `ui.replicas`                          | Web UI k8s deployment replicas. Keep at `1` unless your ingress provides sticky sessions — the Horizon BFF holds the session table in memory                                                                                                                                                                               | `1`                                                                                                                      |
| `ui.image.repository`                  | Horizon UI container image. Release images: Docker Hub `apache/skywalking-ui` tagged `horizon-x.y.z`. Dev images: `ghcr.io/apache/skywalking-horizon-ui`                                                                                                                                                                   | `skywalking.docker.scarf.sh/apache/skywalking-ui`                                                                        |
| `ui.image.tag`                         | Horizon UI image tag (required), e.g. `horizon-1.0.0`. Horizon releases independently of OAP and 1.0.0 works against OAP 10.4.0 and 11.x alike (for 10.x also set `ui.config.templates.mode: readonly`). The legacy booster UI is not supported — `apache/skywalking-ui` publishes no 11.x tag                                                                                                                                                                                                                                                                      | `null`                                                                                                                   |
| `ui.image.pullPolicy`                  | Web UI container image pull policy                                                                                                                                                                                                                                                                                         | `IfNotPresent`                                                                                                           |
| `ui.nodeAffinity`                      | Web UI node affinity policy                                                                                                                                                                                                                                                                                                | `{}`                                                                                                                     |
| `ui.nodeSelector`                      | Web UI labels for pod assignment                                                                                                                                                                                                                                                                                           | `{}`                                                                                                                     |
| `ui.tolerations`                       | Web UI tolerations                                                                                                                                                                                                                                                                                                         | `[]`                                                                                                                     |
| `ui.ingress.enabled`                   | Create Ingress for Web UI                                                                                                                                                                                                                                                                                                  | `false`                                                                                                                  |
| `ui.ingress.annotations`               | Associate annotations to the Ingress                                                                                                                                                                                                                                                                                       | `{}`                                                                                                                     |
| `ui.ingress.path`                      | Associate path with the Ingress                                                                                                                                                                                                                                                                                            | `/`                                                                                                                      |
| `ui.ingress.hosts`                     | Associate hosts with the Ingress                                                                                                                                                                                                                                                                                           | `[]`                                                                                                                     |
| `ui.ingress.tls`                       | Associate TLS with the Ingress                                                                                                                                                                                                                                                                                             | `[]`                                                                                                                     |
| `ui.service.type`                      | Web UI svc type                                                                                                                                                                                                                                                                                                            | `ClusterIP`                                                                                                              |
| `ui.service.externalPort`              | external port for the service                                                                                                                                                                                                                                                                                              | `80`                                                                                                                     |
| `ui.service.internalPort`              | internal port for the service (Horizon BFF binds 8081)                                                                                                                                                                                                                                                                     | `8081`                                                                                                                   |
| `ui.service.externalIPs`               | external IP addresses                                                                                                                                                                                                                                                                                                      | `nil`                                                                                                                    |
| `ui.service.loadBalancerIP`            | Load Balancer IP address                                                                                                                                                                                                                                                                                                   | `nil`                                                                                                                    |
| `ui.service.annotations`               | Kubernetes service annotations                                                                                                                                                                                                                                                                                             | `{}`                                                                                                                     |
| `ui.service.nodePort`                  | Node port when `ui.service.type` is `NodePort`                                                                                                                                                                                                                                                                             | not set (auto-allocated)                                                                                                 |
| `ui.service.loadBalancerSourceRanges`  | Limit load balancer source IPs to a list of CIDRs (where available)                                                                                                                                                                                                                                                        | not set (commented out in `values.yaml`)                                                                                 |
| `ui.securityContext`                   | Pod [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod). The image runs as the non-root `horizon` user; `fsGroup` makes mounted volumes group-writable for that user                                                                             | `fsGroup: 101`                                                                                                           |
| `ui.livenessProbe`                     | TCP liveness probe. Targets the container's named `page` port, so it follows `ui.service.internalPort` instead of pinning a number that can drift                                                                                                                                                                          | `tcpSocket.port: page` <br> `initialDelaySeconds: 30` <br> `periodSeconds: 20`                                           |
| `ui.readinessProbe`                    | HTTP readiness probe against the named `page` port; verifies the BFF is up and the auth backend is healthy. `/api/auth/health` is the only unauthenticated BFF health endpoint                                                                                                                                             | `httpGet.path: /api/auth/health` <br> `httpGet.port: page` <br> `initialDelaySeconds: 10` <br> `periodSeconds: 10` <br> `failureThreshold: 6` |
| `ui.persistence.enabled`               | Mount a PVC at `/data` for audit log / setup / alarm state / wire debug log. When `false`, state lands in the container's writable layer and is lost on pod restart                                                                                                                                                        | `false`                                                                                                                  |
| `ui.persistence.existingClaim`         | Use a pre-created PVC; when unset, the chart creates one                                                                                                                                                                                                                                                                   | not set (commented out in `values.yaml`)                                                                                 |
| `ui.persistence.storageClass`          | Storage class for the chart-managed PVC (`-` renders an empty `storageClassName`)                                                                                                                                                                                                                                          | not set (commented out in `values.yaml`)                                                                                 |
| `ui.persistence.accessModes`           | PVC access modes                                                                                                                                                                                                                                                                                                           | `[ReadWriteOnce]`                                                                                                        |
| `ui.persistence.size`                  | PVC size                                                                                                                                                                                                                                                                                                                   | `1Gi`                                                                                                                    |
| `ui.persistence.annotations`           | Annotations applied to the chart-managed PVC                                                                                                                                                                                                                                                                               | `{}`                                                                                                                     |
| `ui.resources`                         | UI node resources requests & limits                                                                                                                                                                                                                                                                                        | `{}`                                                                                                                     |
| `ui.podAnnotations`                    | Annotations applied to all UI pods                                                                                                                                                                                                                                                                                         | not set (commented out in `values.yaml`)                                                                                 |
| `ui.config`                            | `horizon.yaml` content (deep-merged onto chart defaults that point `oap.queryUrl`/`adminUrl`/`zipkinUrl` at the in-cluster OAP; `zipkinUrl` is derived from `oap.ports.zipkin-query` and only resolves to a usable URL when that port is set, and `server.publicUrl` is derived from `ui.ingress.hosts[0]` when an ingress is enabled). See the [horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md). Empty by default: the chart-computed values are written as `${HORIZON_*:<in-cluster default>}` tokens, so anything not set here stays overridable by env via `ui.extraEnv` / `ui.envFromSecret`. A field set here as a literal makes its `HORIZON_*` env var inert | `{}`                                                                                                                     |
| `ui.config.templates.mode`             | `live` reads/writes dashboard templates through OAP 11's `/ui-management/templates*` admin REST API; `readonly` renders the templates bundled in the image and makes the config surface display-only. Set `readonly` against OAP 10.4.0 — it has no such REST surface, and `live` blocks every layer-driven page. Changing this needs a BFF restart | `live`                                                                                                                   |
| `ui.config.server.publicUrl`           | Public base URL operators reach Horizon at; used for SSO callbacks and as the OAuth issuer. Derived from the first `ui.ingress.hosts` entry when an ingress is enabled; set explicitly to override                                                                                                                          | derived, else `""`                                                                                                       |
| `ui.config.server.trustProxy`          | Whether to believe `X-Forwarded-For` for the client address in the login audit. Use a hop count (`1` = one proxy in front) or the ingress address/CIDR; `true` is refused at boot                                                                                                                                           | `false`                                                                                                                  |
| `ui.envFromSecret`                     | Reference a Secret whose keys are exposed as env vars in the BFF container, for use with `${VAR}` interpolation in `ui.config` (e.g. admin password hash)                                                                                                                                                                  | `""`                                                                                                                     |
| `ui.extraEnv`                          | Extra env vars passed to the BFF container                                                                                                                                                                                                                                                                                 | `[]`                                                                                                                     |
| `ui.extraVolumes`                      | Extra volumes for the UI pod. Needed by the two Horizon settings that take a filesystem path: `auth.tokensFile` (API tokens Secret) and `sourceMaps.bootMountDir` (durable `.map` files at `/app/sourcemaps`)                                                                                                              | `[]`                                                                                                                     |
| `ui.extraVolumeMounts`                 | Extra volume mounts for the BFF container, paired with `ui.extraVolumes`                                                                                                                                                                                                                                                   | `[]`                                                                                                                     |
| `oapInit.nodeAffinity`                 | OAP init job node affinity policy                                                                                                                                                                                                                                                                                          | `{}`                                                                                                                     |
| `oapInit.nodeSelector`                 | OAP init job labels for master pod assignment                                                                                                                                                                                                                                                                              | `{}`                                                                                                                     |
| `oapInit.tolerations`                  | OAP init job tolerations                                                                                                                                                                                                                                                                                                   | `[]`                                                                                                                     |
| `oapInit.extraPodLabels`               | OAP init job metadata labels                                                                                                                                                                                                                                                                                               | `{}` |
| `oapInit.ttlSecondsAfterFinished`      | Seconds after which the finished OAP init Job (and its Pod) is auto-deleted by the Kubernetes TTL-after-finished controller. Empty keeps the Job. Leave empty with GitOps tools (Argo CD/Flux), which would recreate it after deletion.                                                                                       | `""`                                                                                                                     |
| `satellite.name`                       | Satellite deployment name                                                                                                                                                                                                                                                                                                  | `satellite`                                                                                                              |
| `satellite.replicas`                   | Satellite k8s deployment replicas                                                                                                                                                                                                                                                                                          | `1`                                                                                                                      |
| `satellite.enabled`                    | Is enable Satellite                                                                                                                                                                                                                                                                                                        | `false`                                                                                                                  |
| `satellite.image.repository`           | Satellite container image name                                                                                                                                                                                                                                                                                             | `skywalking.docker.scarf.sh/apache/skywalking-satellite`                                                                 |
| `satellite.image.tag`                  | Satellite container image tag. No default; required only when `satellite.enabled=true`, and the render then fails with `satellite.image.tag is required`                                                                                                                                                                    | `null`                                                                                                                   |
| `satellite.image.pullPolicy`           | Satellite container image pull policy                                                                                                                                                                                                                                                                                      | `IfNotPresent`                                                                                                           |
| `satellite.antiAffinity`               | Satellite anti-affinity policy                                                                                                                                                                                                                                                                                             | `soft`                                                                                                                   |
| `satellite.nodeAffinity`               | Satellite node affinity policy                                                                                                                                                                                                                                                                                             | `{}`                                                                                                                     |
| `satellite.nodeSelector`               | Satellite labels for pod assignment                                                                                                                                                                                                                                                                                        | `{}`                                                                                                                     |
| `satellite.tolerations`                | Satellite tolerations                                                                                                                                                                                                                                                                                                      | `[]`                                                                                                                     |
| `satellite.service.type`               | Satellite svc type                                                                                                                                                                                                                                                                                                         | `ClusterIP`                                                                                                              |
| `satellite.ports.grpc`                 | Satellite grpc port for tracing, metrics, logs, events                                                                                                                                                                                                                                                                     | `11800`                                                                                                                  |
| `satellite.ports.prometheus`           | Satellite http port for Prometheus monitoring                                                                                                                                                                                                                                                                              | `1234`                                                                                                                   |
| `satellite.resources`                  | Satellite node resources requests & limits                                                                                                                                                                                                                                                                                 | `{} - cpu limit must be an integer`                                                                                      |
| `satellite.podAnnotations`             | Configurable [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/) applied to all Satellite pods                                                                                                                                                                                   | not set                                                                                                                  |
| `satellite.env`                        | Satellite environment variables                                                                                                                                                                                                                                                                                            | not set                                                                                                                  |
| `satellite.config`                     | Extra files written into `/skywalking/config` (e.g. `satellite_config.yaml`), keyed by path                                                                                                                                                                                                                                 | `{}`                                                                                                                     |
| `satellite.ports.pprof`                | Satellite pprof port; enable only when debugging Satellite                                                                                                                                                                                                                                                                 | not set (commented out in `values.yaml`)                                                                                 |
| `satellite.securityContext`            | Allows you to set the [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) for the pod                                                                                                                                                         | `{}` |

### Elasticsearch (ECK)

Elasticsearch is deployed via [ECK (Elastic Cloud on Kubernetes)](https://github.com/elastic/cloud-on-k8s).
The chart includes the ECK operator and an `eck-elasticsearch` subchart, both controlled by `elasticsearch.enabled`.
Because Elasticsearch CRDs must exist before the ES custom resource can be created, the ECK operator CRDs need to be installed separately before deploying the chart. See the main [README](../../README.md) for installation steps.

#### Top-level parameters

| Parameter | Description | Default |
|---|---|---|
| `elasticsearch.enabled` | Deploy the ECK operator and an ECK-managed Elasticsearch cluster | `true` |
| `elasticsearch.version` | Elasticsearch version to deploy | `8.18.8` |
| `elasticsearch.fullnameOverride` | Override the Elasticsearch resource name. The ECK service will be `{name}-es-http` | `""` |
| `elasticsearch.labels` | Labels applied to the Elasticsearch resource | `{}` |
| `elasticsearch.annotations` | Annotations applied to the Elasticsearch resource | `{}` |
| `elasticsearch.http` | HTTP layer settings. TLS is disabled by default for OAP connectivity | `tls.selfSignedCertificate.disabled: true` |
| `elasticsearch.secureSettings` | [Secure settings](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-es-secure-settings.html) to inject from Kubernetes secrets | `[]` |
| `elasticsearch.updateStrategy` | [Update strategy](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-update-strategy.html) controlling simultaneous changes | `{}` |
| `elasticsearch.volumeClaimDeletePolicy` | Policy for PVC deletion on scale-down or cluster deletion | `""` |
| `elasticsearch.ingress.enabled` | Enable ingress to expose Elasticsearch externally | `false` |
| `elasticsearch.ingress.annotations` | Annotations on the Elasticsearch Ingress | `{}` |
| `elasticsearch.ingress.hosts` | Hosts for the Elasticsearch Ingress, each `{host, path}` | `[{host: chart-example.local, path: /}]` |
| `elasticsearch.ingress.tls.enabled` | Enable TLS on the Elasticsearch Ingress (`secretName` alongside it) | `false` |

#### External Elasticsearch (when `elasticsearch.enabled` is `false`)

| Parameter | Description | Default |
|---|---|---|
| `elasticsearch.config.host` | Elasticsearch host | `elasticsearch` |
| `elasticsearch.config.port.http` | Elasticsearch HTTP port | `9200` |
| `elasticsearch.config.user` | Elasticsearch user (optional) | `""` |
| `elasticsearch.config.password` | Elasticsearch password (optional) | `""` |

#### Node sets (`elasticsearch.nodeSets[]`)

ECK [node sets](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-node-configuration.html) define the topology of the Elasticsearch cluster. Each entry in the list creates a group of Elasticsearch nodes.

| Parameter | Description | Default |
|---|---|---|
| `nodeSets[].name` | Name of the node set | `default` |
| `nodeSets[].count` | Number of Elasticsearch nodes in this set | `3` |
| `nodeSets[].config` | Elasticsearch configuration (e.g. `node.store.allow_mmap`, `node.roles`) | `node.store.allow_mmap: false` |
| `nodeSets[].volumeClaimTemplates` | Persistent storage for Elasticsearch data. Left unset (commented out) in `values.yaml`, so ECK applies its own default: a 1Gi `elasticsearch-data` PVC per node on the default StorageClass — enough to start, not to keep | not set |

#### Pod template (`elasticsearch.nodeSets[].podTemplate`)

The pod template follows standard Kubernetes Pod spec nested under `podTemplate.spec`. This controls scheduling, resources, init containers, etc.

| Parameter | Description | Default |
|---|---|---|
| `podTemplate.metadata.annotations` | Pod annotations (e.g. `iam.amazonaws.com/role`) | `{}` |
| `podTemplate.metadata.labels` | Extra pod labels | `{}` |
| `podTemplate.spec.affinity` | Pod [affinity](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-advanced-node-scheduling.html) rules | not set |
| `podTemplate.spec.nodeSelector` | Node selector for pod assignment | not set |
| `podTemplate.spec.tolerations` | Pod tolerations | not set |
| `podTemplate.spec.imagePullSecrets` | Image pull secrets | not set |
| `podTemplate.spec.priorityClassName` | Priority class name | not set |
| `podTemplate.spec.terminationGracePeriodSeconds` | Grace period for pod termination | not set |
| `podTemplate.spec.initContainers` | Init containers (e.g. sysctl `vm.max_map_count`) | not set |
| `podTemplate.spec.containers[].resources` | Container resource requests & limits | `requests: 100m cpu, 2Gi mem` <br> `limits: 2Gi mem` |
| `podTemplate.spec.containers[].env` | Environment variables (e.g. `ES_JAVA_OPTS`) | not set |
| `podTemplate.spec.containers[].securityContext` | Container-level security context | not set (ECK managed) |

### BanyanDB

`banyandb.enabled` is `false` by default. The keys below are read by *this* chart's templates in
both modes; everything else under `banyandb.*` belongs to the
[subchart](../storage/banyandb.md).

| Parameter | Description | Default |
|---|---|---|
| `banyandb.enabled` | Deploy BanyanDB as a subchart. When `false`, `banyandb.config.*` points at an external cluster | `false` |
| `banyandb.image.tag` | BanyanDB server version. A subchart key with no usable default — required once `banyandb.enabled=true` | `""` |
| `banyandb.config.grpcAddress` | External BanyanDB gRPC address; becomes `SW_STORAGE_BANYANDB_TARGETS`. Ignored when `banyandb.enabled=true` — the address is then computed from the subchart Service | `banyandb-grpc:17912` |
| `banyandb.config.httpAddress` | External BanyanDB HTTP address, polled by the `wait-for-banyandb` init container. Same override rule | `banyandb-http:17913` |
| `banyandb.auth.enabled` | Send credentials to BanyanDB. Also a subchart key, so it configures both ends | `false` |
| `banyandb.auth.users` | Credential list; the chart passes `users[0]` to OAP as `SW_STORAGE_BANYANDB_USER` / `SW_STORAGE_BANYANDB_PASSWORD` | `[{username: admin, password: banyandb}]` |
| `banyandb.standalone.enabled` / `banyandb.cluster.enabled` | Subchart topology toggles; the chart also reads them to pick the Service ports to wait on | `true` / `false` |

### PostgreSQL

`postgresql.enabled` is `false` by default, and the bundled deployment is a demo — `values.yaml`
turns persistence off on both primary and read replicas.

| Parameter | Description | Default |
|---|---|---|
| `postgresql.enabled` | Deploy the bundled Bitnami PostgreSQL. Not for production | `false` |
| `postgresql.config.host` | Hostname of your own PostgreSQL. Used **only** when `postgresql.enabled` is `false`; otherwise the host is `<release-name>-postgresql` | `postgresql-service.your-awesome-company.com` |
| `postgresql.containerPorts.postgresql` | Port used in `SW_JDBC_URL` and by the `wait-for-postgresql` init container | `5432` |
| `postgresql.auth.database` | Database name in `SW_JDBC_URL` | `skywalking` |
| `postgresql.auth.username` / `postgresql.auth.password` | Credentials OAP connects with (`SW_DATA_SOURCE_USER` / `SW_DATA_SOURCE_PASSWORD`) | `postgres` / `123456` |
| `postgresql.auth.postgresPassword` | Superuser password for the bundled deployment | `123456` |

Specify each parameter with the `--set key=value[,key=value]` argument to `helm install`. A bare
`skywalking` is not a chart reference — use a local path or the OCI URL. (The legacy JFrog repo
that served the name `skywalking/skywalking` is frozen at `4.3.0`.) From a clone, with the ECK
CRDs already installed as their own release:

```shell
helm install myrelease chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false \
  --set nameOverride=my-skywalking
```

Resource names are built from the release name and `nameOverride`, so it has to be RFC 1123
lowercase: `newSkywalking` renders `myrelease-newSkywalking-oap`, which templates fine and is then
rejected by the API server.

Alternatively, put the values in a YAML file:

```shell
helm install my-release chart/skywalking -f my-values.yaml
```

Released versions install from the OCI reference instead —
`oci://registry-1.docker.io/apache/skywalking-helm --version <x.y.z>`. See
[Chart sources](../install/chart-sources.md).

> **Tip**: You can use the default [values.yaml](../../chart/skywalking/values.yaml)

### RBAC Configuration

Roles and RoleBindings resources will be created automatically for `OAP` .

> **Tip**: You can refer to the default `oap-role.yaml` file in [templates](../../chart/skywalking/templates/) to customize your own.

### Ingress TLS

If your cluster allows automatic create/retrieve of TLS certificates (
e.g. [kube-lego](https://github.com/jetstack/kube-lego)), please refer to the documentation for that mechanism.

To manually configure TLS, first create/retrieve a key & certificate pair for the address(skywalking ui) you wish to
protect. Then create a TLS secret in the namespace:

```console
kubectl create secret tls skywalking-tls --cert=path/to/tls.cert --key=path/to/tls.key
```

Include the secret's name, along with the desired hostnames, in the skywalking-ui Ingress TLS section of your
custom `values.yaml` file:

```yaml
ui:
  ingress:
    ## If true, Skywalking ui server Ingress will be created
    ##
    enabled: true

    ## Skywalking ui server Ingress hostnames
    ## Must be provided if Ingress is enabled
    ##
    hosts:
      - skywalking

    ## Skywalking ui server Ingress TLS configuration
    ## Secrets must be manually created in the namespace
    ##
    tls:
      - secretName: skywalking
        hosts:
          - skywalking
```

### Envoy ALS

Envoy ALS(access log service) provides fully logs about RPC routed, including HTTP and TCP.

If you want to open envoy ALS, you can do this by modifying values.yaml. default open.

```yaml
serviceAccounts:
  oap:
    create: true
```

When envoy als ,will give ServiceAccount clusterrole permission.
More envoy als ,please refer
to https://github.com/apache/skywalking/blob/master/docs/en/setup/envoy/als_setting.md#observe-service-mesh-through-als
