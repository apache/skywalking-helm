# Scaling and the OAP Cluster

How this chart forms an OAP cluster on Kubernetes, which values control replica count, pod spreading
and sizing, and why the UI must stay at a single replica.

## How OAP replicas find each other

The chart runs OAP in Kubernetes cluster mode. `SW_CLUSTER` is hardwired to `kubernetes` in
`chart/skywalking/templates/oap-deployment.yaml` — the chart exposes no dedicated value for
switching to `standalone`, `zookeeper`, `etcd`, etc. Four environment variables drive it, all
rendered by the chart:

| Env var | Rendered from | Example (`helm install skywalking ... -n sw`) |
|---|---|---|
| `SW_CLUSTER` | hardwired | `kubernetes` |
| `SW_CLUSTER_K8S_NAMESPACE` | `.Release.Namespace` | `sw` |
| `SW_CLUSTER_K8S_LABEL` | `skywalking.oap.labels` helper | `app=skywalking,release=skywalking,component=oap` |
| `SKYWALKING_COLLECTOR_UID` | downward API, `metadata.uid` | the pod's own UID |

The label selector is built from the release name and `oap.name`, and it matches exactly the labels
the OAP Deployment puts on its pods. Each OAP pod watches pods in its own namespace carrying those
labels, treats every Ready peer as a cluster member at *pod IP + the core gRPC port*, and uses
`SKYWALKING_COLLECTOR_UID` to recognise which of those pods is itself.

Two consequences worth knowing:

- **Cluster membership is namespace-scoped.** Two releases in different namespaces never join each
  other. Two releases in the *same* namespace do not join either, because `release=` is part of the
  selector.
- **The peer port is OAP's configured core gRPC port, not `oap.ports.grpc`.** `oap.ports.grpc`
  only declares the container port and the Service port; the chart does not set `SW_CORE_GRPC_PORT`.
  If you change `oap.ports.grpc` away from `11800`, set the matching backend property too:

```shell
--set oap.ports.grpc=21800 \
--set oap.env.SW_CORE_GRPC_PORT=21800
```

## The RBAC that makes it work

Watching pods requires permission, so `serviceAccounts.oap.create: true` (the default) creates a
ServiceAccount, a namespaced Role + RoleBinding, and a ClusterRole + ClusterRoleBinding, all bound to
the OAP pods:

| Template | Scope | Grants (`get`, `watch`, `list` only) |
|---|---|---|
| `oap-role.yaml` | namespace | `pods`, `configmaps` |
| `oap-clusterrole.yaml` | cluster | `pods`, `pods/log`, `endpoints`, `services`, `nodes`, `namespaces`, `configmaps`; `extensions` `deployments`/`replicasets`; `networking.istio.io` `serviceentries` |

The Role is the part cluster formation depends on (`pods` for peer discovery, `configmaps` for
`oap.dynamicConfig.enabled`). The ClusterRole covers OAP's cluster-wide Kubernetes features —
Kubernetes monitoring and service-mesh metadata. Everything is read-only; nothing is granted `create`,
`update` or `delete`.

If you set `serviceAccounts.oap.create: false`, **none of those five objects are rendered** — the
`{{- if .Values.serviceAccounts.oap.create }}` guard wraps the ServiceAccount, both roles and both
bindings. You must then supply `serviceAccounts.oap.name` and grant that account at least the
namespaced `pods` read permission yourself, or OAP starts and never discovers a peer.

## Scaling OAP

`oap.replicas` defaults to `2`. It maps straight to the Deployment's `spec.replicas`.

```shell
helm install skywalking \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set oap.replicas=3
```

or afterwards:

```shell
# the Deployment carries the same labels the cluster selector uses
kubectl scale deployment -n <namespace> \
  -l app=<release>,release=<release>,component=oap --replicas=3
```

(A `kubectl scale` is transient — the next `helm upgrade` resets it to `oap.replicas`.)

Notes:

- Scaling is safe at any time. New pods join by label, and existing pods pick them up from the pod
  informer once they report Ready.
- **Scaling via `helm upgrade` re-runs schema init.** The init Job's name carries a hash of *all*
  chart values, `oap.replicas` included, so changing the replica count creates a fresh Job and runs
  `-Dmode=init` again. That is harmless — init is idempotent and the running OAP pods are untouched
  — but expect a new `*-oap-init-*` Job on every scale. See [The OAP Init Job](oap-init-job.md).
  A `kubectl scale` bypasses Helm entirely and creates no Job.
- The E2E tests run with `--set oap.replicas=1`; a single replica is a valid configuration and still
  uses Kubernetes cluster mode (it simply discovers a one-member cluster).
- The chart ships **no HorizontalPodAutoscaler and no PodDisruptionBudget**. Add your own if you
  need them.

## Spreading pods across nodes

`oap.antiAffinity` accepts `soft` (default) or `hard`, and controls what goes into the pod's
`affinity.podAntiAffinity`. Both forms select on the same three labels (`app`, `release`,
`component`) with `topologyKey: kubernetes.io/hostname`.

`soft` renders a preference:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            app: "skywalking"
            release: "skywalking"
            component: "oap"
```

`hard` renders a requirement:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: "kubernetes.io/hostname"
        labelSelector:
          matchLabels:
            app: "skywalking"
            release: "skywalking"
            component: "oap"
```

With `hard`, at most one OAP pod runs per node — so `oap.replicas` greater than the number of
schedulable nodes leaves the surplus pods `Pending` forever. Any other value (including `""`) renders
no `podAntiAffinity` at all; the `if`/`else if` chain matches only these two strings.

The remaining scheduling knobs are passed through verbatim:

| Value | Default | Rendered as |
|---|---|---|
| `oap.nodeAffinity` | `{}` | `affinity.nodeAffinity` |
| `oap.nodeSelector` | `{}` | `spec.nodeSelector` |
| `oap.tolerations` | `[]` | `spec.tolerations` |

The same three exist for `ui.*`, `oapInit.*` and `satellite.*`; `satellite.antiAffinity` behaves
identically to the OAP one.

## Sizing a replica

`oap.resources` is `{}` by default — the container ships with no requests and no limits. The
`values.yaml` example uses whole CPU cores, and the chart's values reference notes that the CPU limit
must be an integer:

```yaml
oap:
  resources:
    limits:
      cpu: 8
      memory: 8Gi
    requests:
      cpu: 8
      memory: 4Gi
```

`oap.javaOpts` defaults to `-Xmx2g -Xms2g` and is **appended to a fixed prefix**, not substituted for
it. The rendered variable is:

```yaml
- name: JAVA_OPTS
  value: "-Dmode=no-init -Xmx2g -Xms2g"
```

`-Dmode=no-init` is what keeps the OAP pods out of schema initialisation (the init Job owns that).
Because your value replaces the whole default string, always carry the heap flags forward:

```shell
--set oap.javaOpts="-Xmx6g -Xms6g -XX:+UseG1GC"
```

Keep the heap comfortably below the memory limit — the container also needs off-heap and metaspace
room, or the kubelet OOM-kills the pod mid-startup. Increasing `oap.replicas` is generally the better
lever than a very large single heap.

## Why the UI stays at one replica

`ui.replicas` defaults to `1` and should stay there unless you add sticky sessions. Horizon UI's BFF
holds the active session table **in process memory**. With two replicas behind a plain round-robin
Service, roughly every other request lands on a pod that has never seen your session, so logins break
and the UI bounces users back to the login page.

For the same reason the UI Deployment uses:

```yaml
strategy:
  type: Recreate
```

instead of the default `RollingUpdate` — Recreate tears the old pod down before starting the new one,
so there is never a window with two pods serving traffic from disjoint session tables. The trade-off
is a short outage on every UI upgrade or config change, which is the intended behaviour here. Note
that the UI pod also rolls whenever `horizon.yaml` changes, via a `checksum/config` annotation over
the rendered ConfigMap.

Two more things tie the UI to a single pod:

- `ui.persistence.enabled` is `false` by default, so `/data` is an `emptyDir`. Turning it on
  provisions one PVC with `accessModes: [ReadWriteOnce]` for the audit log, setup state, alarm state
  and wire debug log — a second replica on another node cannot attach it.
- `ui.livenessProbe`/`ui.readinessProbe` target the BFF on `8081`; readiness uses
  `/api/auth/health`, the only unauthenticated health endpoint.

If you genuinely need more than one UI pod, you must supply sticky sessions at the ingress
(for example `nginx.ingress.kubernetes.io/affinity: cookie` on an ingress-nginx controller via
`ui.ingress.annotations`), switch `ui.persistence` to a `ReadWriteMany` class or disable it, and
accept that a rolling update is now your responsibility to make safe. Scaling the UI is not a
supported configuration of this chart; scale OAP instead — that is where the query load actually
lands. See [Horizon UI in This Chart](../ui/horizon-ui.md) and
[UI Service and Ingress](../expose/ui-service-and-ingress.md).

## Related

- [The OAP Init Job](oap-init-job.md) — schema creation, and why OAP runs in `no-init` mode
- [Configure OAP](oap-configuration.md) — `oap.env`, `oap.config`, dynamic configuration
- [Satellite Gateway](satellite.md) — `satellite.replicas` and its own anti-affinity
- [skywalking Chart Values](../reference/skywalking-chart-values.md) — the full parameter table
- [Install and Startup Failures](../troubleshooting/install-and-startup.md) — pods `Pending` or
  restarting
- [SkyWalking Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/)
  — every `SW_*` variable, including the `cluster.kubernetes` block
