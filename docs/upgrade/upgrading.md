# Upgrade

How to run `helm upgrade` on this chart, the labels a release keeps or gets from 5.1.0 on, and the
breaking changes chart 5.0.0 brings — the booster UI removal, the OAP 11
dashboard-template changes, and the new `ui.config` default.

## Run the upgrade

```shell
helm upgrade skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --wait --wait-for-jobs
```

Three values have no defaults and must be present on **every** upgrade, not just the first install:

| value | example |
|---|---|
| `oap.image.tag` | `11.0.0` |
| `oap.storageType` | `elasticsearch`, `postgresql`, `banyandb` |
| `ui.image.tag` | `horizon-1.0.0` (only when `ui.enabled` is true) |

`helm upgrade` does not remember `--set` flags from the previous release, so either repeat them,
pass a values file with `-f`, or add `--reuse-values`. `--wait-for-jobs` alongside `--wait` makes
Helm report an init-Job failure directly instead of leaving you to guess why OAP never went Ready.

## Labels and selectors

Since 5.1.0 the chart uses the Kubernetes
[recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/):
`app.kubernetes.io/name` (always the chart name, `skywalking-helm`), `app.kubernetes.io/instance`
(the release name), `app.kubernetes.io/component` (`oap`, `ui`, `satellite`, `oap-init`),
`app.kubernetes.io/managed-by` and `helm.sh/chart`. Which labels a release carries, and which its
selectors match on, depends on when it was first installed, because Kubernetes never lets a
Deployment's selector change:

| | Installed with 5.1.0 or later | Installed before 5.1.0 |
|---|---|---|
| Labels on resources and pods | The recommended labels only | `app`, `release`, `component`, `chart`, `heritage`, plus the recommended labels |
| Deployment, Service and anti-affinity selectors | The recommended labels | `app`, `release`, `component` |
| OAP cluster discovery and dynamic configuration, Satellite's OAP lookup | The recommended labels | `app`, `release`, `component` |

`helm upgrade` needs no extra step for either. The chart tells them apart with Helm's `lookup`: when
the release's OAP, UI or Satellite Deployment already exists and selects by `release`, the release
keeps the old style, and a Deployment created later in it, such as Satellite enabled after the
upgrade, gets the same style. The pods of an older release roll once to pick up the recommended
labels.

The `kubectl -l` commands in these docs use the recommended labels, which every release carries from
5.1.0 on. Your own selectors, NetworkPolicies and monitors keep working on a release installed before
5.1.0; on a new release, write them against the recommended labels.

To see which style a release uses:

```shell
kubectl get deployment -n skywalking \
  -o custom-columns='NAME:.metadata.name,RELEASE:.metadata.annotations.meta\.helm\.sh/release-name,SELECTOR:.spec.selector.matchLabels'
```

The OAP init Job keeps its pod labels as they were, because a Job's pod template is immutable.
Whether init runs again depends on the Job's name, which hashes the computed values, chart defaults
included, and not on the labels. From 5.0.0, an Elasticsearch or PostgreSQL release keeps its Job and
has it relabelled in place. A release with the bundled BanyanDB runs init once more, because the
BanyanDB subchart's defaults changed in 5.1.0.

### Argo CD and other tools that render without cluster access

`lookup` returns nothing when the chart is rendered without cluster access: Argo CD,
`helm template | kubectl apply`, and `helm upgrade --dry-run=client`. There the chart cannot see the
existing Deployments and renders the labels of a new release. For a release installed before 5.1.0,
set:

```yaml
labelStyle: legacy
```

**Without it, OAP and the UI become unreachable.** The Services switch to the recommended labels,
while Kubernetes rejects the new Deployment selectors with `spec.selector: ... field is immutable`,
so the running pods never get labels the Services match. Set the value and sync again to recover. A
release first installed with 5.1.0 or later needs nothing. The value is left out of the init Job's
name hash, so setting or removing it does not run init again.

For the same reason, a preview rendered without cluster access shows the new labels for an existing
release, although the real upgrade keeps the old ones. `helm upgrade --dry-run=server` previews what
the upgrade will actually apply.

### Moving an existing release to the new labels

This is optional. Delete the three Deployments and upgrade: with no Deployment left to inherit from,
Helm renders the release like a new one and moves everything to the recommended labels, the
selectors and OAP discovery included. OAP, the UI and Satellite are down until the new pods are
Ready. Storage, ConfigMaps and the UI's PersistentVolumeClaim are kept. The init Job gets a new name
and runs once more, because its pod's labels change with the style.

```shell
# A release installed before 5.1.0 still has the release label.
# This must list only the OAP, UI and Satellite Deployments of this release.
kubectl get deployment -n skywalking -l release=skywalking
kubectl delete deployment -n skywalking -l release=skywalking
helm upgrade skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.1.0 -n skywalking -f my-values.yaml
```

With Argo CD, remove `labelStyle: legacy` in the same change, then sync. Anything of your own that
selects by the old labels stops matching once the release has moved.

After the move, `helm rollback` to a revision from before it fails on the same three Deployments,
because their selector would change back. Delete them first; they no longer carry the `release`
label, so select them by the recommended labels:

```shell
kubectl delete deployment -n skywalking \
  -l app.kubernetes.io/name=skywalking-helm,app.kubernetes.io/instance=skywalking
helm rollback skywalking <revision> -n skywalking
```

## Chart 5.0.0 is a version set

OAP and BanyanDB are hard-coupled and must move together — that pair is the most common upgrade
failure. Horizon releases independently of OAP (1.0.0 covers both OAP 10.4.0 and 11.x), so its tag
is pinned separately, but it must be a `horizon-*` tag: the chart no longer supports booster UI.

| component | value | version |
|---|---|---|
| chart | `--version` | `5.0.0` |
| OAP | `oap.image.tag` | `11.0.0` |
| Horizon UI | `ui.image.tag` | `horizon-1.0.0` |
| BanyanDB | `banyandb.image.tag` | `0.11.0` |

OAP ships the BanyanDB server API versions it accepts in
`SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS`. OAP 11.0.0 accepts API `0.11`, which maps to
BanyanDB release `0.11.x`. The check is an exact string match with no lenient fallback, so OAP 11
against BanyanDB 0.10.x refuses to start with `Incompatible BanyanDB server API version`. The
mapping is published at
[BanyanDB API versions](https://skywalking.apache.org/docs/skywalking-banyandb/latest/installation/versions/);
see also [BanyanDB](../storage/banyandb.md).

The bump from `4.9.0` to `5.0.0` is a major one because the UI image line, several `values.yaml`
keys and the init Job's identity all changed incompatibly. The rest of this page is that list.

## Breaking: booster UI is gone

OAP 11 deleted `apm-webapp` — the Armeria reverse proxy behind the `skywalking/ui` image — along
with the `skywalking-ui` git submodule and the `docker.ui` Maven target. The last booster image
published to `apache/skywalking-ui` is `10.4.0`; there is no `11.x` tag and there will not be one.
Only `horizon-*` tags are published going forward.

What to change when coming from a release that ran booster UI:

| | before (4.9.0) | after (5.0.0) |
|---|---|---|
| image tag | `ui.image.tag=<oap-version>` | `ui.image.tag=horizon-1.0.0` |
| container port | `8080` | `8081` (`ui.service.internalPort`; Service still fronts `80`) |
| OAP admin port | no `oap.ports.admin` key at all | `oap.ports.admin: 17128`, required |
| login | none — booster was unauthenticated | must be configured — no fallback |
| `/graphql` on the UI | proxied to OAP | **not proxied**; call OAP directly |
| UI env | `ui.env` (map); chart set `SW_OAP_ADDRESS` / `SW_ZIPKIN_ADDRESS` | `ui.extraEnv` (list) and `ui.envFromSecret`; OAP URLs come from the `horizon.yaml` ConfigMap |
| Zipkin port keys | `oap.ports.zipkinreceiver` / `zipkinquery` | `oap.ports.zipkin-receiver` / `zipkin-query` |

`ui.env` no longer exists — a values file that still sets it renders nothing and the BFF gets no
extra environment. The Zipkin keys were renamed too: `oap-deployment.yaml` reads them as
`zipkin-receiver` / `zipkin-query`, so a carried-over `zipkinquery` still opens a container port but
no longer sets `SW_QUERY_ZIPKIN` / `SW_QUERY_ZIPKIN_REST_PORT`, and the UI's `oap.zipkinUrl` is not
derived.

**Configure logins before you cut over.** Horizon has no built-in `admin/admin`, and the BFF does
**not** fail closed: with no users it boots, logs an error, serves the login page, and answers
`/api/auth/health` with 200 — which is the chart's own readiness probe. The pod goes Ready and
nobody can sign in. See [Set Up Logins](../ui/logins.md).

**Expose the OAP admin port.** OAP 11 serves `/status/*` and `/debugging/*` on the admin REST port
only, and Horizon's BFF reads inspect, DSL debugging, runtime rules and (in the default
`templates.mode: live`) the dashboard template store from it. `oap.ports.admin` defaults to `17128`;
set it to `null` on any OAP 10.x release — the admin server is an OAP 11 addition.

**Retarget `swctl` and any other GraphQL caller.** The BFF does not pass `/graphql` through to OAP,
so anything that used to query the UI must address the OAP Service:

```shell
# before
swctl --base-url=http://skywalking-skywalking-helm-ui/graphql service ls

# after — OAP directly, on oap.ports.rest
swctl --display yaml \
  --base-url=http://skywalking-skywalking-helm-oap:12800/graphql \
  service ls
```

Point it at the OAP Service on `12800`; copy the form from
there if you need the in-cluster hostname pattern.

### Upgrading the UI first

Horizon 1.0.0 runs against OAP 10.4.0 as well as OAP 11.x, so you can split the move in two: swap
the UI while still on OAP 10, then upgrade OAP. On OAP 10 add one setting, because OAP 10 does not
serve the `/ui-management` REST API Horizon reads templates from:

```shell
--set ui.config.templates.mode=readonly
```

That renders the templates bundled in the image and makes the configuration surface display-only.
Dashboards, traces, logs, topology, alarms and profiling all work. Remove it once OAP is on 11. The
mode is read at boot, so it needs a BFF restart — the UI Deployment's `checksum/config` annotation
rolls the pod for you whenever the ConfigMap changes.

## Breaking: OAP 11 removed the UI template seeds

These OAP-side surfaces went with the bundled UI. If your values still set them, they are read by
nothing — delete them:

| removed | where it used to live |
|---|---|
| `ui-initialized-templates` | a key under `oap.config`, seeding on-disk dashboard JSON |
| `SW_ENABLE_UPDATE_UI_TEMPLATE` | an env var under `oap.env` |
| sidebar menu storage | OAP storage |
| `UIConfigurationManagement` GraphQL queries and mutations | OAP query API |

The on-disk dashboard seed files were deleted along with `UITemplateInitializer`. Horizon ships its
own dashboard library and manages templates over the admin REST port instead — that is what
`oap.ports.admin` and `ui.config.templates.mode` are for.

## Breaking: `ui.config` is empty by default

The interim Horizon work on `main` mounted a ConfigMap of literal values over `/app/horizon.yaml`.
As of 5.0.0 `ui.config` defaults to `{}` and the ConfigMap carries only the fields the chart has to
compute:

| field | derived from |
|---|---|
| `oap.queryUrl` | the in-cluster OAP Service and `oap.ports.rest` |
| `oap.adminUrl` | the in-cluster OAP Service and `oap.ports.admin` |
| `oap.zipkinUrl` | the OAP Service and `oap.ports.zipkin-query`, only when that port is set |
| `server.publicUrl` | the first `ui.ingress.hosts` entry, only when `ui.ingress.enabled` and `ui.ingress.hosts` are both set (`https` when `ui.ingress.tls` is non-empty) |
| `server.port` | `ui.service.internalPort`, so the BFF binds the port the container exposes |

The four URLs are written as `${VAR:default}` **tokens**, not literals, so the in-cluster value is
only the default and the matching `HORIZON_*` variable still wins. `server.port` is the deliberate
exception — the chart writes it as a plain number, because the container port and both probes are
derived from `ui.service.internalPort` and the BFF has to bind that same port.

This matters because Horizon expands `${...}` over the raw *text* of the config file before parsing
it. A field written as a literal makes its `HORIZON_*` environment variable silently inert, and a
field the file omits falls back to a schema default that consults the environment for only a
fraction of the image's variables. A config file full of literals therefore does not merely
duplicate defaults — it disables most of the image's configuration surface.

**If you are carrying a full `ui.config` block forward** — from the pre-release `main` values, not
from 4.x, which had no `ui.config` at all — drop every field that only restates what the image
already sets (`server.host`, `oap.timeoutMs`, `auth.backend`, `rbac.enabled`, `session.*` and
`templates.mode` all did), and move the rest to `ui.extraEnv` or `ui.envFromSecret`:

| config field | how to set it now |
|---|---|
| `templates.mode` | `HORIZON_TEMPLATES_MODE` — works as a bare env var |
| `session.cookieSecure` | keep in `ui.config`, optionally as `${HORIZON_SESSION_COOKIE_SECURE:false}` |
| `server.trustProxy` | keep in `ui.config`, optionally as `${HORIZON_TRUST_PROXY:false}` |
| `auth.local.users` | keep in `ui.config` as `${HORIZON_AUTH_LOCAL_USERS:[]}` + `ui.envFromSecret` |
| `oap.auth` | keep in `ui.config` as `${HORIZON_OAP_AUTH:null}` + `ui.envFromSecret` |

Only the first row works from a bare environment variable. The other four have literal schema
defaults, so their `HORIZON_*` variables are reachable **only** through a `${...}` token in the
mounted file — set the variable without the token and nothing happens, with no error. See
[Configure Horizon](../ui/configure.md).

`ui.config` is still there for pinning a field regardless of the environment, and `${VAR}` tokens
you write in it do expand — that is how the Secret pattern works. See
[Configure Horizon](../ui/configure.md).

## The init Job re-runs on every upgrade that changes a value

The storage schema is created by a one-shot `*-oap-init-*` Job that runs OAP with `-Dmode=init`; the
main Deployment runs `-Dmode=no-init` and blocks until the schema exists. The Job name carries a
`sha256` of the chart values, so any `helm upgrade` that changes a value produces a new Job name and
re-runs init automatically, with Helm pruning the previous one. An upgrade that changes nothing
reuses the existing Job.

Before 5.0.0 this Job was a `post-install,post-upgrade,post-rollback` Helm hook with a fixed name —
the OAP Service name plus `-init`, e.g. `skywalking-skywalking-helm-oap-init`. Helm does not own
hook resources, so an upgrade from 4.9.0 leaves that completed Job behind in the namespace. It is
inert; delete it by hand.

To force a rerun without changing a value, delete the Job and upgrade again:

```shell
# The release's current init Job, read from its rendered manifest: right for any chart version and
# either label style. With `helm template | kubectl apply`, pipe your rendered output into the same
# awk instead; `kubectl apply` never prunes a Job that a values change replaced.
kubectl delete job -n skywalking "$(helm get manifest skywalking -n skywalking | awk '/^kind: Job$/ {j=1} j && /^  name:/ {gsub(/"/, "", $2); print $2; exit}')"
# Keep the chart version the release already runs (see `helm list -n skywalking`): an older
# version would also roll back the release's labels and selectors.
helm upgrade skywalking oci://docker.io/apache/skywalking-helm \
  --version <current chart version> -n skywalking --reuse-values
```

More detail in [The OAP Init Job](../operate/oap-init-job.md).

## Rolling back

`helm rollback` restores the previous release's manifests, so image tags and configuration revert.
It does **not** revert anything the init Job wrote to storage — the chart has no downgrade path for
the storage schema. Before an OAP major upgrade, make sure the storage backend is one you can
restore independently.

If the UI comes back Ready but unusable after an upgrade, start at
[UI and Login Problems](../troubleshooting/ui-and-login.md); if OAP or the init Job fails, see
[Install and Startup Failures](../troubleshooting/install-and-startup.md).
