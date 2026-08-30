# Run the E2E Tests

Every change to this chart is validated by an end-to-end suite that installs `chart/skywalking` into
a throwaway [kind](https://kind.sigs.k8s.io/) cluster, pushes real traffic through it, and then asks
**Horizon UI's BFF** the questions an operator would ask. Nothing in the suite talks to the OAP's
GraphQL endpoint directly — that would test the OAP, not the chart. Five cells run in CI, covering
two OAP lines against two storage backends. This page explains how they are put together and how to
run one on your own machine.

## The framework

The tests are driven by [skywalking-infra-e2e](https://github.com/apache/skywalking-infra-e2e). Each
config file under `test/e2e/` is one complete test: the cluster to create, the setup steps to run,
the traffic to generate, and the assertions to make. The phases are:

| Phase | What it does here |
| --- | --- |
| `setup` | Creates the kind cluster from `file: kind28.yaml`, loads `init-system-environment: env` into the shell environment, then runs the `steps:` in order — install tooling, install Istio, `helm install` the chart, deploy bookinfo, start traffic. Each step may declare `wait:` conditions; the whole phase has `timeout: 25m`. |
| `trigger` | Unused. All five cells generate load with a `wrk` Deployment (`test/e2e/traffic-gen.yaml`) applied as a setup step, so no cell has a `trigger:` block. |
| `verify` | Runs each `query:` and matches its output against a template in `test/e2e/expected/`, retrying on `retry: {count: 30, interval: 10s}`. |
| `cleanup` | No cell declares `cleanup:`, so infra-e2e's own default applies — `always` when `CI=true` (GitHub Actions always tears down), `success` otherwise. A locally *failed* run therefore leaves the cluster up for debugging. |

`kind.expose-ports` is what makes the verify phase possible. Every cell exposes exactly one service:

```yaml
kind:
  expose-ports:
    - namespace: istio-system
      resource: service/skywalking-ui
      port: 80
```

infra-e2e port-forwards it and exports two shell variables named after the resource and the port —
`${service_skywalking_ui_host}` and `${service_skywalking_ui_80}` — which every verify case
interpolates into a base URL. The OAP's own ports are not exposed at all.

`expected/*.yml` are templates, not literals. They use matchers such as `{{- contains .services }}`
and `{{ notEmpty .version }}`, so a case asserts "these services are present" or "this field has a
value", not an exact payload.

## The five cells

All five run the same fixture — kind `kindest/node:v1.28.15` (one control plane, three workers),
namespace `istio-system`, `fullnameOverride=skywalking`, `oap.replicas=1`, Satellite enabled, Horizon
UI at `$UI_REPO:$UI_TAG` — and differ in which OAP and which storage they install, plus the flags
each of those pairings needs.

| File | OAP | Storage | Distinguishing flags |
| --- | --- | --- | --- |
| `test/e2e/e2e-oap11-elasticsearch.yaml` | `$OAP_REPO:$OAP_TAG` (11.0.0) | `oap.storageType=elasticsearch` against the ECK subchart, left on by the chart's `elasticsearch.enabled: true` | Pre-installs the ECK CRDs out of `chart/skywalking/charts/eck-operator-3.3.1.tgz` and passes `eck-operator.installCRDs=false`. |
| `test/e2e/e2e-oap11-banyandb-standalone.yaml` | 11.0.0 | BanyanDB 0.11 (`$BANYANDB_REPO:$BANYANDB_TAG`) | `oap.storageType=banyandb`, `elasticsearch.enabled=false`, `banyandb.enabled=true`, `banyandb.standalone.enabled=true`, `banyandb.cluster.enabled=false`, `banyandb.auth.enabled=true`. |
| `test/e2e/e2e-oap11-banyandb-cluster.yaml` | 11.0.0 | BanyanDB 0.11, cluster mode | As above but `banyandb.standalone.enabled=false`, `banyandb.cluster.enabled=true`. |
| `test/e2e/e2e-oap10-elasticsearch.yaml` | `$OAP_10_REPO:$OAP_10_TAG` (10.4.0) | ECK Elasticsearch, with the same CRD pre-install and `eck-operator.installCRDs=false` as the cell above | `oap.ports.admin=null`, `ui.config.templates.mode=readonly`. |
| `test/e2e/e2e-oap10-banyandb.yaml` | 10.4.0 | BanyanDB 0.10.3 (`$BANYANDB_0_10_REPO:$BANYANDB_0_10_TAG`), standalone with auth | `oap.ports.admin=null`, `ui.config.templates.mode=readonly`. |

The three OAP 11 cells also switch Zipkin on — `oap.ports.zipkin-query=9412` plus
`SW_RECEIVER_ZIPKIN=default` and `SW_QUERY_ZIPKIN=default` — because the chart only emits
`oap.zipkinUrl` into Horizon's config when that port is set, and one verify case asserts Horizon can
reach it.

### How the OAP 10.4 cells differ

The admin host, and the `/ui-management` template store mounted on it, arrived in OAP 11. On 10.4
the chart must not render an admin port (`oap.ports.admin=null`) and Horizon must run its template
store from the bundle in its own image (`ui.config.templates.mode=readonly`).

The important part is what happens to the assertions: they are **inverted, not dropped**. Those
Horizon endpoints answer HTTP 200 either way and report the failure in the body, so the 10.4 cells
still call them and expect the negative answer:

| Case | OAP 11 expects | OAP 10.4 expects |
| --- | --- | --- |
| `GET /api/preflight?refresh=1` | `expected/horizon-admin-live.yml` — `adminReachable: true`, `templatesMode: live`, `uiManagement: true` | `expected/horizon-admin-readonly.yml` — `adminReachable: false`, `templatesMode: readonly` |
| `GET /api/admin/templates/sync-status?force=true` | `expected/horizon-templates-live.yml` — `mode: live`, `unreachable: false` | `expected/horizon-templates-readonly.yml` — `mode: readonly`, `unreachable: false` |

`unreachable: false` in readonly mode is the point of that second row: readonly still serves
templates, from the image, without ever contacting the OAP. The OAP 10.4 cells run six verify cases
to the OAP 11 cells' seven — the missing one is the Zipkin check, since they do not enable Zipkin.

## The traffic fixture: everything lands in `MESH`

This is the single most useful fact for anyone adding a case. There is no Java agent anywhere in
this suite. Each cell:

1. installs Istio with the demo profile and Envoy ALS pointed at the chart's Satellite —
   `meshConfig.defaultConfig.envoyAccessLogService.address=skywalking-satellite.istio-system:11800`
   and `meshConfig.enableEnvoyAccessLogService=true` — then labels `default` with
   `istio-injection=enabled`;
2. installs the chart with `SW_ENVOY_METRIC_ALS_HTTP_ANALYSIS=k8s-mesh` and
   `SW_ENVOY_METRIC_ALS_TCP_ANALYSIS=k8s-mesh`;
3. deploys [bookinfo](https://istio.io/latest/docs/examples/bookinfo/) from the `$ISTIO_VERSION`
   manifests and runs `wrk` against `http://istio-ingressgateway.istio-system:80/productpage`.

So every service the tests can see is synthesized by the OAP from Envoy access logs, and it lands in
the **`MESH`** layer — never `GENERAL`. A verify case that queries `/api/layer/GENERAL/services`
will find nothing, no matter how long it retries.

Service names come from two places that must agree: `K8S_SERVICE_NAME_RULE='e2e::${service.metadata.name}'`
on the OAP command line, and `oap.config."metadata-service-mapping.yaml"` in `test/e2e/values.yaml`,
which maps the Istio canonical-name label to `e2e::<name>`. That is why the assertions look for
`e2e::productpage` and `e2e::reviews`.

## How an assertion works

Every verify case shells out to `test/e2e/script/horizon.sh`, which does what an operator does: log
in, keep the session cookie, then call an API with it.

```
horizon.sh <base-url> get  <api-path>
horizon.sh <base-url> post <api-path> <json-body>
```

It `POST`s to `/api/auth/login` with `curl --fail-with-body -c "$JAR"`, fails loudly unless the
response actually set a `horizon_sid` cookie, and reuses that jar (`-b "$JAR"`) for the real request.
Credentials come from `HORIZON_USERNAME` / `HORIZON_PASSWORD` and default to `admin`/`admin`.

The JSON that comes back is piped through `yq` into a small projection, and *that* is what the
`expected/` template matches. One case verbatim, from `test/e2e/e2e-oap11-elasticsearch.yaml`:

```yaml
    - query: |
        bash test/e2e/script/horizon.sh http://${service_skywalking_ui_host}:${service_skywalking_ui_80} get /api/layer/MESH/services | yq -p json -o yaml '{"layer": .layer, "services": ([.services[].name] | sort)}'
      expected: expected/horizon-mesh-services.yml
```

and the template it matches, `test/e2e/expected/horizon-mesh-services.yml` (below its license
header):

```yaml
layer: MESH
services:
  {{- contains .services }}
  - e2e::productpage
  - e2e::reviews
  {{- end }}
```

The `yq` projection is deliberate: pull out the two or three fields that carry the meaning, sort
anything order-dependent, and keep the expected file small enough to read.

## Two traps

Both of these cost real debugging time, so they are commented in the cell files as well.

**`/api/layer/:key/services` returns `reachable: true` with an empty list even when the OAP is
down.** Asserting on `.reachable` there proves nothing — the case would pass against a dead backend.
Assert on the service *names*, as the case above does.

**infra-e2e's `notEmpty` matcher rejects numbers.** It only accepts nil or a string
(`notEmpty only supports nil or string type, but was ...`), so a numeric assertion has to be turned
into a boolean in the `yq` projection before it reaches the template. That is what the `service_cpm`
case does:

```yaml
        ... | yq -p json -o yaml '{"reachable": .reachable, "id": .widgets[0].id, "positive": (.widgets[0].value != null and .widgets[0].value > 0)}'
```

against `expected/horizon-service-cpm.yml`, which expects `positive: true` alongside
`reachable: true` and `id: cpm`. Use `notEmpty` for strings such as `.version`; compare numbers
yourself.

## Login: the chart ships no users

`chart/skywalking/values.yaml` sets `ui.config: {}`, and Horizon has no built-in `admin/admin`
fallback — a fresh install has nobody who can log in until you configure `auth`, which is exactly
what [Set Up Logins](../ui/logins.md) is about.

`test/e2e/values.yaml` seeds two local users — `admin`/`admin` (role `admin`) and
`skywalking`/`skywalking` (roles `viewer`, `maintainer`) — as argon2id hashes. **Every cell must
therefore pass `-f test/e2e/values.yaml`**, or the very first `horizon.sh` call fails at the login
step. That failure is the intended signal, not a flake.

The same overlay carries the other two things the tests need on top of chart defaults:

- `oap.config."metadata-service-mapping.yaml"` — the `e2e::` service naming described above.
- `elasticsearch.nodeSets` — a single 2Gi ES node with `node.store.allow_mmap: false` and relaxed
  disk watermarks, so ES stays green on a kind node with little free disk.

The first verify case in every cell (`GET /api/auth/me` against `expected/horizon-me.yml`) asserts
`username: admin` with `roles: [admin]`, which proves the overlay was applied before anything else
is tested.

## `test/e2e/env` — the image pin file

Every cell loads this file via `init-system-environment`, so it is the single place where the
versions under test are pinned.

| Variable | Pins | Moves? |
| --- | --- | --- |
| `OAP_REPO` / `OAP_TAG` | `docker.io/apache/skywalking-oap-server` : `11.0.0` | Yes — this is the current line. |
| `UI_REPO` / `UI_TAG` | `docker.io/apache/skywalking-ui` : `horizon-1.0.0` | Yes. Dev images live on GHCR (`apache/skywalking-horizon-ui`) if CI needs an unreleased fix. |
| `BANYANDB_REPO` / `BANYANDB_TAG` | `ghcr.io/apache/skywalking-banyandb` at commit `3b83e18…` | Yes. A GHCR commit pin rather than `docker.io/apache/skywalking-banyandb:0.11.0` **on purpose**: that commit *is* the v0.11.0 tag, and naming it pins the exact source under test instead of a tag that can be re-pushed. The release image is published; user-facing install docs quote it. |
| `SATELLITE_REPO` / `SATELLITE_TAG` | `ghcr.io/apache/skywalking-satellite/skywalking-satellite` at a commit tag | Yes. |
| `OAP_10_REPO` / `OAP_10_TAG` | `docker.io/apache/skywalking-oap-server` : `10.4.0` | **No — frozen.** 10.4.0 is the last v10 release. |
| `BANYANDB_0_10_REPO` / `BANYANDB_0_10_TAG` | `docker.io/apache/skywalking-banyandb` : `0.10.3` | **No — frozen.** OAP 10.4.0 pins `compatibleServerApiVersions` to BanyanDB API 0.10, so this pair never moves again. |

The OAP 11 line moves as a trio: OAP 11.0.0 accepts BanyanDB server API 0.11 only, and Horizon 1.0.0
is the UI tested against it — see [Version Compatibility](../evaluate/version-compatibility.md).
The BanyanDB *chart* version is not pinned here; it comes from `chart/skywalking/Chart.yaml`.

## Run one locally

You need Docker and Go — the `e2e` binary embeds kind as a library, so no separate `kind` binary is
required. The setup steps install `yq`, `kubectl`, `istioctl` and `helm` into `/usr/local/bin` and
install Istio into the cluster, so run this on a machine you don't mind changing.

Build the `e2e` CLI once:

```shell
git clone https://github.com/apache/skywalking-infra-e2e.git
cd skywalking-infra-e2e
make install DESTDIR=/usr/local/bin
```

Then, **from the root of this repo** (the config files reference `chart/skywalking` and
`test/e2e/…` relative to the working directory):

```shell
export ISTIO_VERSION=1.24.0
e2e run -c test/e2e/e2e-oap11-banyandb-standalone.yaml
```

`ISTIO_VERSION` is set by the CI workflow, not by `test/e2e/env`, and both `install-istioctl.sh` and
the bookinfo manifest URLs read it — export it yourself when running locally.

To iterate without re-creating the cluster, run the phases separately:

```shell
e2e setup   -c test/e2e/e2e-oap11-banyandb-standalone.yaml
e2e verify  -c test/e2e/e2e-oap11-banyandb-standalone.yaml   # repeat as you debug
e2e cleanup -c test/e2e/e2e-oap11-banyandb-standalone.yaml   # deletes the kind cluster
```

While the cluster is up:

```shell
kubectl -n istio-system get pods
kubectl -n istio-system logs deploy/skywalking-oap
kubectl -n istio-system logs deploy/skywalking-ui          # Horizon's BFF, where the API calls land
kubectl -n istio-system port-forward svc/skywalking-ui 8080:80   # then log in as admin/admin
```

With that port-forward running you can also drive the script by hand, exactly as the verify phase
does:

```shell
bash test/e2e/script/horizon.sh http://localhost:8080 get /api/layer/MESH/services | yq -p json
```

## How CI runs them

`.github/workflows/e2e.ci.yaml` runs the suite from one matrix job, `als`, with `fail-fast: false`
and a matrix of five entries — one per cell — each with a 60-minute timeout, so one failing storage
backend does not cancel the other four:

```yaml
strategy:
  fail-fast: false
  matrix:
    test:
      - name: Horizon + OAP 11 + Elasticsearch
        config: test/e2e/e2e-oap11-elasticsearch.yaml
      # …and the two OAP 11 BanyanDB cells plus the two OAP 10.4 cells
```

Each entry logs in to `ghcr.io` (the Satellite and BanyanDB 0.11 images live there), sets up Go 1.24,
and hands its config file to the `apache/skywalking-infra-e2e` action, pinned to SHA `8c21e43e…`:

```yaml
- uses: apache/skywalking-infra-e2e@8c21e43e241a32a54bdf8eeceb9099eb27e5e9b4
  with:
    e2e-file: $GITHUB_WORKSPACE/${{ matrix.test.config }}
```

The workflow sets `ISTIO_VERSION: 1.24.0` in its top-level `env:`. On failure it dumps disk usage
and the local Docker images, then uploads `$SW_INFRA_E2E_LOG_DIR` as the `logs` artifact — start
there when a CI run fails but a local run passes. A trailing `build` job depends on `als` and only
runs `echo`, so one job name aggregates the whole matrix.

The workflow runs on every `pull_request` and on pushes to `master`. The `paths-ignore: ['**.md']`
filter applies only to the push trigger, so a docs-only pull request still runs the full matrix.

## Adding a case

1. Add the `query:` to **all five** cells unless it is version-specific, and put the expectation in
   `test/e2e/expected/`. If the answer differs between OAP 11 and 10.4, invert it into a second
   expected file rather than skipping the case — see the table above.
2. Go through `test/e2e/script/horizon.sh`. Anything that calls the OAP directly is testing the OAP.
3. Query the `MESH` layer, and project the response with `yq` down to the fields that carry meaning.
4. Keep image references as `$OAP_REPO` / `$OAP_TAG` style variables so `test/e2e/env` stays the only
   place versions are pinned.

## Adding a cell

Copy the closest existing file, change the storage flags, and **add a matrix entry in
`.github/workflows/e2e.ci.yaml`** — a config file that is not in the matrix never runs. See
[Elasticsearch](../storage/elasticsearch.md) and [BanyanDB](../storage/banyandb.md) for what those
storage flags mean outside the tests.
