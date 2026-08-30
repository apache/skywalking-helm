# Upgrade

How to run `helm upgrade` on this chart, and the breaking changes chart 5.0.0 brings — the booster
UI removal, the OAP 11 dashboard-template changes, and the new `ui.config` default.

## Run the upgrade

```shell
helm upgrade skywalking oci://registry-1.docker.io/apache/skywalking-helm \
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
kubectl delete job -n skywalking -l release=skywalking
helm upgrade skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --reuse-values
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
