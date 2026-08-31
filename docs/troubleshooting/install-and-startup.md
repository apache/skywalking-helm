# Install and Startup Failures

Symptom → cause → fix for everything between `helm install` and the first Ready OAP pod: template
errors, hanging `--wait`, init containers that never finish, and OAP crash loops.

Examples below assume release `skywalking` in namespace `skywalking`. With that release name the
chart's resources are `skywalking-skywalking-helm-oap`, `-ui`, and a one-shot Job named
`skywalking-skywalking-helm-oap-init-<hash>` (add `--set fullnameOverride=skywalking` to get the
short `skywalking-oap` names instead).

## Triage first

```shell
helm status skywalking -n skywalking
kubectl get pods,jobs -n skywalking
kubectl describe pod -n skywalking -l component=oap
kubectl logs -n skywalking -l release=skywalking --all-containers --tail=200
```

`kubectl describe` is where init-container state (`Init:0/1`, `Init:Error`) and probe/OOM kill
reasons appear; `kubectl logs -l release=skywalking` covers the OAP pods, the UI pod and the init
Job pod in one shot.

---

## Helm fails before anything is created

### `execution error at (...): ui.image.tag is required`

```text
Error: execution error at (skywalking-helm/templates/ui-deployment.yaml:77:52): ui.image.tag is required
Error: execution error at (skywalking-helm/templates/oap-init.job.yaml:83:53): oap.image.tag is required
Error: execution error at (skywalking-helm/templates/oap-init.job.yaml:92:12): oap.storageType is required
```

**Cause.** Three values have no default and are wrapped in Helm's `required` function. Rendering
stops at the first one missing, so with none of them set you hit them one at a time, in the order
above.

**Fix.** Set all three (and `satellite.image.tag` too, if `satellite.enabled=true`):

| value | example | notes |
|---|---|---|
| `oap.image.tag` | `11.0.0` | |
| `oap.storageType` | `elasticsearch` | also `banyandb`, `postgresql` |
| `ui.image.tag` | `horizon-1.0.0` | must be a `horizon-*` tag |
| `satellite.image.tag` | `v0.4.0` | only when `satellite.enabled=true` |

### `no matches for kind "Elasticsearch" ... ensure CRDs are installed first`

```text
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest:
resource mapping not found for name: "skywalking-elasticsearch" ... no matches for kind
"Elasticsearch" in version "elasticsearch.k8s.elastic.co/v1": ensure CRDs are installed first
```

**Cause.** `elasticsearch.enabled` is `true` (the default) so the chart renders an `Elasticsearch`
custom resource. The `eck-operator` dependency ships its CRDs as ordinary templates in the *same*
release, and Helm has to map every object against the API server before it applies any of them —
so the CR cannot be validated in the install that would also create its CRD.

**Fix.** Install the CRDs as their own release first, then tell the chart not to install them again:

```shell
helm install eck-crds eck-operator-crds \
  --repo https://helm.elastic.co --version 3.3.1 \
  -n skywalking --create-namespace

helm install skywalking oci://docker.io/apache/skywalking-helm --version 5.0.0 \
  -n skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

Only `elasticsearch.enabled=false` switches this off: both subcharts are gated on that value alone,
so pointing `oap.storageType` at `banyandb` or `postgresql` still renders the ECK CRDs and the
`Elasticsearch` CR. Add `--set elasticsearch.enabled=false` and the step does not apply.

### `exists and cannot be imported into the current release`

```text
Error: INSTALLATION FAILED: Unable to continue with install: CustomResourceDefinition
"elasticsearches.elasticsearch.k8s.elastic.co" in namespace "" exists and cannot be imported
into the current release: invalid ownership metadata
```

**Cause.** The ECK CRDs are already owned by another release (your `eck-crds` release, or an ECK
operator installed cluster-wide earlier) and `eck-operator.installCRDs` is still `true`, so this
release tries to claim them too. CRDs are cluster-scoped — only one release can own them.

**Fix.** `--set eck-operator.installCRDs=false`. Note that the `eck-operator` and `elasticsearch`
subcharts share one condition (`elasticsearch.enabled`) — you cannot install the CR without the
operator through this chart. If a full ECK operator already runs in the cluster, set
`elasticsearch.enabled=false` and point OAP at the existing cluster with `elasticsearch.config.*`
(see [Elasticsearch](../storage/elasticsearch.md)).

---

## `helm install` hangs, then times out

### `Error: ... timed out waiting for the condition` with `--wait`

**Cause.** With `--wait`, Helm blocks until every resource is Ready. The OAP Deployment runs with
`JAVA_OPTS="-Dmode=no-init ..."`: it deliberately keeps port `12800` closed until the storage
schema exists, and the schema is created by the one-shot `*-oap-init-*` Job. So a hang means the
init Job has not succeeded — it is failing, or still waiting on storage.

The init Job is a **normal release resource**, not a Helm hook, precisely so this resolves: Job and
Deployment run in the same install phase. (A `post-install` hook would deadlock forever — Helm
waits for the Deployment to be Ready before running post-hooks, and the Deployment is waiting for
the hook.)

**Fix.** Add `--wait-for-jobs` so Helm surfaces the Job's failure directly instead of only
reporting that OAP never became Ready, and read the Job's logs:

```shell
kubectl get jobs -n skywalking
kubectl logs -n skywalking -l component=skywalking-skywalking-helm-job --tail=200
```

Then work down the list below: the Job's own `wait-for-*` init container is the usual culprit.
See [The OAP Init Job](../operate/oap-init-job.md) for the full mechanism.

### OAP pod is `Running` but never Ready

**Cause.** Same handshake seen from the pod side: `no-init` OAP is alive but has not opened `12800`
because the schema is missing. Either the init Job never ran, or it failed. The pod stays at `0/1`
and its `RESTARTS` count climbs every ~5 minutes, as the default startup-probe budget expires.

**Fix.** Confirm the Job completed, and if it is missing, re-run it:

```shell
kubectl get jobs -n skywalking          # want COMPLETIONS 1/1
kubectl delete job -n skywalking -l release=skywalking
helm upgrade skywalking <chart> -n skywalking --reuse-values
```

Helm recreates the deleted Job and init runs again. The Job's name carries a hash of the chart
values, so any `helm upgrade` that changes a value re-runs init on its own — an upgrade that
changes nothing leaves the identical Job in place and does **not** re-run it.

---

## Pods never get past init

### Pod stuck in `Init:0/1`

**Cause.** The `wait-for-storage` init container (attached to both the OAP Deployment and the init
Job) is still polling the storage backend. What it polls depends on `oap.storageType`:

| `oap.storageType` | init container | probe | budget |
|---|---|---|---|
| `elasticsearch` | `wait-for-elasticsearch` (`busybox:1.30`) | `nc -z -w3 <es-http> 9200` | 60 tries, 5s apart, then `exit 1` |
| `banyandb` | `wait-for-banyandb` (`curlimages/curl`) | `curl -k <http addr>/api/healthz` | 60 tries, 5s apart, then `exit 1` |
| `postgresql` | `wait-for-postgresql` (`postgres:13`) | `pg_isready -h <host> -p 5432 -U <user>` | **unbounded** — retries every 3s forever |

The PostgreSQL loop never gives up, so a wrong host there shows as a pod that sits in `Init:0/1`
indefinitely rather than erroring. Check what it is actually waiting on:

```shell
kubectl logs -n skywalking -l component=oap -c wait-for-postgresql
kubectl get pods,svc -n skywalking   # is the backend even scheduled?
```

**Fix.** Usually the backend itself is not up yet (see the Pending entry below) — wait. If the
address is wrong, correct it: `elasticsearch.config.host` / `.port.http`,
`banyandb.config.httpAddress`, or `postgresql.config.host` for external backends; for embedded
ones the addresses are derived by the chart and a mismatch means the subchart is disabled or
renamed (`*.fullnameOverride`).

### Pod goes `Init:Error` / `Init:CrashLoopBackOff` after about five minutes

**Cause.** The Elasticsearch or BanyanDB wait container exhausted its 60 × 5s budget and exited
`1`. The pod restarts and tries again, so this repeats until storage answers.

**Fix.** Same as above — but five minutes of silence normally means the backend is broken or
unreachable, not slow. For the embedded ECK path, check the Elasticsearch resource and its pods:

```shell
kubectl get elasticsearch,pods -n skywalking
kubectl logs -n skywalking -l elasticsearch.k8s.elastic.co/cluster-name=skywalking-elasticsearch
```

### Storage pods stay `Pending`

**Cause.** The default Elasticsearch topology is **3 nodes** (`elasticsearch.nodeSets[0].count: 3`)
each requesting `2Gi` of memory, and each ES node also takes a PersistentVolume from the default
StorageClass (ECK's own default claim — the chart ships `nodeSets[0].volumeClaimTemplates`
commented out). BanyanDB claims volumes for its data nodes in cluster mode
(`banyandb.storage.data.enabled: true`); BanyanDB standalone
(`banyandb.storage.standalone.enabled: false`) and the demo PostgreSQL
(`postgresql.primary.persistence.enabled: false`) claim none. A laptop-sized cluster usually has
neither the memory nor a default StorageClass.

**Fix.** `kubectl describe pod` names the reason (`Insufficient memory`, `no persistent volumes
available`). Shrink the cluster the way the e2e suite does — `test/e2e/values.yaml` sets
`count: 1` — or switch to BanyanDB standalone. See [Requirements](../evaluate/requirements.md).

### `ImagePullBackOff` on the UI image

```text
Failed to pull image "skywalking.docker.scarf.sh/apache/skywalking-ui:11.0.0": manifest unknown
```

**Cause.** `ui.image.tag` was set to the OAP version. Horizon UI releases independently and its
images are tagged `horizon-<x.y.z>`; there is no `11.0.0` tag on `apache/skywalking-ui`.

**Fix.** `--set ui.image.tag=horizon-1.0.0`. Dev builds live at
`ghcr.io/apache/skywalking-horizon-ui` and need `ui.image.repository` changed too. The legacy
booster UI is not supported by this chart — see [Horizon UI in This Chart](../ui/horizon-ui.md).

---

## OAP starts and then dies

### OAP restarts every few minutes during a cold start

**Cause.** The startup probe budget ran out. The default `startupProbe` is a TCP check on `12800`
with `failureThreshold: 30` and `periodSeconds: 10` — a 300-second budget covering storage startup
*plus* schema creation by the init Job. On a slow cluster (cold image pulls, a large Elasticsearch
coming up, a big BanyanDB schema) 300s can be too short, and the kubelet restarts a pod that was
legitimately waiting.

**Fix.** Raise the budget — `oap.startupProbe` is empty by default and, when set, replaces the
whole block:

```yaml
oap:
  startupProbe:
    tcpSocket:
      port: 12800
    failureThreshold: 90    # 90 * 10s = 15 minutes
    periodSeconds: 10
```

Do not "fix" this by loosening `livenessProbe` instead: liveness only starts counting once the
startup probe has passed.

### `Incompatible BanyanDB server API version`

**Cause.** OAP and BanyanDB are version-locked. OAP ships the list of server API versions it
accepts in `SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS`; **OAP 11.0.0 accepts API `0.11`**,
which maps to BanyanDB release `0.11.x`. Pairing OAP 11 with BanyanDB 0.10.x makes OAP refuse to
start.

**Fix.** Match the versions — `--set banyandb.image.tag=0.11.0` for OAP 11.0.0. The API-version to
release mapping is at
[BanyanDB API versions](https://skywalking.apache.org/docs/skywalking-banyandb/latest/installation/versions/);
the chart-side details are in [BanyanDB](../storage/banyandb.md) and
[Version Compatibility](../evaluate/version-compatibility.md).

### OAP `OOMKilled`

**Cause.** `oap.javaOpts` defaults to `-Xmx2g -Xms2g` while `oap.resources` is `{}`. Adding a memory
limit below roughly 2.5Gi without changing the heap gets the JVM killed as soon as it touches its
heap — the heap alone is 2Gi before metaspace, direct buffers and thread stacks.

**Fix.** Change both together, keeping the limit comfortably above `-Xmx`:

```shell
  --set oap.javaOpts="-Xmx4g -Xms4g" \
  --set oap.resources.limits.memory=6Gi \
  --set oap.resources.requests.memory=6Gi
```

### `pods is forbidden: User "system:serviceaccount:..." cannot list resource "pods"`

**Cause.** OAP always runs with `SW_CLUSTER=kubernetes` in this chart and needs read access to
pods, endpoints, services, nodes, namespaces and configmaps to find its peers. The chart creates
that Role/ClusterRole and binding only when `serviceAccounts.oap.create` is `true`; setting it to
`false` and pointing `serviceAccounts.oap.name` at an unprivileged ServiceAccount leaves OAP unable
to form a cluster.

**Fix.** Either leave `serviceAccounts.oap.create=true`, or grant your own ServiceAccount the same
rules as `chart/skywalking/templates/oap-clusterrole.yaml` and `oap-role.yaml`.

### `FORBIDDEN/12/index read-only / allow delete (api)` in OAP logs

**Cause.** Elasticsearch hit its flood-stage disk watermark (95% by default) and put indices into
read-only mode. Common on kind / small dev clusters where the node disk is shared.

**Fix.** Free disk, or relax the watermarks the way the e2e overlay does in `test/e2e/values.yaml`:

```yaml
elasticsearch:
  nodeSets:
  - name: default
    # nodeSets is a list: your entry replaces the shipped one whole, so `count`
    # (required by the CRD) and `node.store.allow_mmap` have to be repeated here.
    count: 3
    config:
      node.store.allow_mmap: false
      cluster.routing.allocation.disk.watermark.low: 90%
      cluster.routing.allocation.disk.watermark.high: 99%
      cluster.routing.allocation.disk.watermark.flood_stage: 99%
```

Existing indices stay read-only until the block is cleared on the Elasticsearch side.

---

## GitOps: init runs on every reconcile

**Cause.** `oapInit.ttlSecondsAfterFinished` was set. The Kubernetes TTL-after-finished controller
deletes the completed Job, and Argo CD / Flux then see a missing resource and recreate it — so init
re-runs on every reconcile loop.

**Fix.** Leave `oapInit.ttlSecondsAfterFinished` empty (the default) under GitOps. The Job name is
value-hashed, so upgrades already replace it correctly without a TTL; the setting exists only to
tidy finished Jobs in non-GitOps installs.

---

## Still stuck?

- [The OAP Init Job](../operate/oap-init-job.md) — how the `init` / `no-init` handshake works.
- [UI and Login Problems](ui-and-login.md) — the UI is Ready but nobody can log in.
- [BanyanDB](../storage/banyandb.md) · [Elasticsearch](../storage/elasticsearch.md) ·
  [PostgreSQL](../storage/postgresql.md) — backend-specific settings.
- [Requirements](../evaluate/requirements.md) — cluster version, RBAC and volume prerequisites.
- Ask on the mailing list `dev@skywalking.apache.org`, or open an
  [issue](https://github.com/apache/skywalking/issues) with `helm get manifest` output and the
  failing pod's `describe` + logs.
