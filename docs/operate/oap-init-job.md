# The OAP Init Job

The chart creates the storage schema with a one-shot `*-oap-init-*` Job, and the main OAP
Deployment refuses to serve until that Job has finished. This page explains that handshake, why
the Job is deliberately not a Helm hook, and how to watch, rerun, or clean it up.

## The handshake

Two OAP containers from the same image, started with different modes:

| Workload | `JAVA_OPTS` | Behaviour |
| --- | --- | --- |
| `*-oap-init-*` Job | `<oap.javaOpts> -Dmode=init` | Creates the storage schema (Elasticsearch indices / SQL tables / BanyanDB groups), then exits. `restartPolicy: Never`. |
| `*-oap` Deployment | `-Dmode=no-init <oap.javaOpts>` | Never touches the schema. Blocks with port `12800` closed until the schema exists, so the pod is not Ready. |

Order of events on `helm install`:

1. Both the Job pod and the OAP pods run the same `wait-for-storage` init container and block
   until the storage backend answers. For Elasticsearch and BanyanDB it gives up after 60 attempts
   5s apart (at least 5 minutes) and fails; for PostgreSQL it retries `pg_isready` every 3s
   indefinitely.
2. The Job's OAP boots in `init` mode, writes the schema and exits `Completed`.
3. The OAP pods, still blocked in `no-init` mode, see the schema, open `12800`, and pass their
   startup/readiness probes.
4. Helm's `--wait` resolves, because the Job and the Deployment run in the same phase.

Because the OAP pods' readiness depends on the Job, a failing Job shows up as OAP pods stuck in
`0/1 Running` — see [Watching and debugging](#watching-and-debugging) below.

## Why it is not a Helm hook

The Job is a normal release resource, not a `post-install`/`post-upgrade` hook. A hook would
deadlock `helm upgrade --install --wait`:

- Helm waits for every release resource to become Ready **before** it runs `post-*` hooks.
- The OAP Deployment never becomes Ready until the schema exists.
- The schema is created by the hook, which never runs. Helm waits until timeout.

As a main-phase resource the Job runs alongside the Deployment, and the two unblock each other.

To have Helm surface init-Job failures directly — instead of only reporting that OAP never became
Ready — add `--wait-for-jobs` alongside `--wait`:

```shell
helm upgrade --install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --wait --wait-for-jobs
```

## The value-hashed Job name

A Job's `spec.template` is immutable. With a stable name, any `helm upgrade` that changes the pod
template (a new image tag, a new env var) would fail with `field is immutable`. So the name carries
a short hash of the rendered values:

```gotemplate
{{ printf "%s-init-%s" (include "skywalking.oap.fullname" . | trunc 40 | trimSuffix "-")
                       (.Values | toYaml | sha256sum | trunc 8) }}
```

For a release named `skywalking` that renders to, for example:

```text
skywalking-skywalking-helm-oap-init-39aeb14b
```

Consequences worth knowing:

- Any value change produces a new Job name, so `helm upgrade` creates a fresh Job and re-runs init;
  Helm prunes the previous one because it is no longer in the manifest.
- The hash covers the **whole** values tree, including subchart values — an unrelated change
  (a UI setting, a BanyanDB replica count) also re-runs init.
- The OAP name is truncated to 40 characters before the suffix, so the Job name stays inside the
  63-character DNS limit.

## Configuring the Job

The Job reuses the OAP values for everything that must match the server: `oap.image.*`,
`oap.javaOpts`, `oap.env`, `oap.resources`, `oap.securityContext`, the OAP service account, the
storage env vars derived from `oap.storageType`, and the same `oap.config` / `oap.secretMounts`
volumes. Only these `oapInit.*` keys are Job-specific:

| Value | Default | Purpose |
| --- | --- | --- |
| `oapInit.nodeAffinity` | `{}` | Node affinity for the Job pod |
| `oapInit.nodeSelector` | `{}` | Node selector for the Job pod |
| `oapInit.tolerations` | `[]` | Tolerations for the Job pod |
| `oapInit.extraPodLabels` | `{}` | Extra pod labels, e.g. `sidecar.istio.io/inject: "false"` |
| `oapInit.ttlSecondsAfterFinished` | `""` | Auto-delete the finished Job via the TTL-after-finished controller |

A service mesh sidecar is the common reason to set `extraPodLabels` — an injected sidecar keeps the
pod alive after the OAP container exits, so the Job never reports `Complete`:

```yaml
oapInit:
  extraPodLabels:
    sidecar.istio.io/inject: "false"
```

### ttlSecondsAfterFinished and the GitOps caveat

`oapInit.ttlSecondsAfterFinished` is empty by default, so completed Jobs and their pods stay in the
namespace where you can still read their logs. Set it to tidy them up:

```shell
--set oapInit.ttlSecondsAfterFinished=600
```

**Leave it empty when the release is managed by a GitOps tool (Argo CD, Flux).** The TTL controller
deletes the Job, the GitOps reconcile sees a resource missing from the desired state, recreates it,
and init runs again on every sync loop. The value-hashed name already makes upgrades work without
TTL — the setting is only cosmetic cleanup.

## The startup probe budget

Because `no-init` OAP keeps `12800` closed while it waits, the chart's default startup probe is
generous — from `chart/skywalking/values.yaml`:

```yaml
oap:
  startupProbe: {}
  # Boot budget defaults to 30 (failureThreshold) * 10 (periodSeconds) = 300 seconds.
  # In no-init mode OAP keeps port 12800 closed until the OAP init Job has created the storage
  # schema, so the budget must be large enough to cover storage startup + schema creation;
  # otherwise the pod is restarted while it is legitimately waiting for the init Job.
```

That 300-second budget has to cover storage startup **plus** schema creation. A cold Elasticsearch
cluster, a slow PVC, or a first-time BanyanDB group creation can exceed it, and the pod is then
restarted while it was legitimately waiting. Raise it rather than reducing the wait:

```yaml
oap:
  startupProbe:
    tcpSocket:
      port: 12800
    failureThreshold: 90    # 90 * 10s = 15 minutes
    periodSeconds: 10
```

Setting `oap.startupProbe` replaces the default block entirely, so repeat `tcpSocket.port: 12800`.
The liveness and readiness probes default to the same TCP check on `12800` with
`initialDelaySeconds: 5`, `periodSeconds: 10`.

## Watching and debugging

```shell
export NS=skywalking
export RELEASE=skywalking

# The chart renders exactly one Job, whatever the storage type
kubectl get jobs -n "$NS" -l release="$RELEASE"
JOB=$(kubectl get jobs -n "$NS" -l release="$RELEASE" -o jsonpath='{.items[0].metadata.name}')

# Logs (while running, and after completion until the TTL removes it)
kubectl logs -n "$NS" "job/$JOB" --tail=200

# Block until it finishes
kubectl wait --for=condition=complete -n "$NS" "job/$JOB" --timeout=10m
```

Common outcomes:

| Symptom | Cause |
| --- | --- |
| Job pod stuck in `Init:0/1` | `wait-for-storage` cannot reach the backend — wrong host/port, backend not up |
| Job pod `Error` / `BackoffLimitExceeded` | OAP could not create the schema: bad credentials, an incompatible or half-started backend. Read the logs |
| OAP container exited, pod still `Running`, Job never `Complete` | An injected mesh sidecar keeps the pod alive; set `oapInit.extraPodLabels` as above |
| OAP pods `0/1 Running`, restarting every ~5 min | Init never completed, and the startup probe budget expired |

## Forcing a rerun

Every `helm upgrade` with a changed value already reruns init. To rerun it without changing any
value, delete the Job and upgrade — Helm recreates the now-missing resource:

```shell
kubectl delete job -n skywalking -l release=skywalking
helm upgrade skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --reuse-values
```

## See also

- [Configure OAP](oap-configuration.md) — the `oap.env`, `oap.javaOpts` and config-override values the Job inherits
- [Pick a Backend](../storage/choose-a-backend.md) — what "the schema" means per storage type
- [Install and Startup troubleshooting](../troubleshooting/install-and-startup.md)
- [Upgrade](../upgrade/upgrading.md)
- [skywalking chart values](../reference/skywalking-chart-values.md)
