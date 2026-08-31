# Where to Get the Chart

Four places serve this chart; three are current and one is frozen. This page tells you which
address to point `helm install` at, and what each one actually carries.

## Source matrix

| Source | Address | Carries | Use when |
| --- | --- | --- | --- |
| Docker Hub (OCI) | `oci://docker.io/apache/skywalking-helm` | Released `skywalking-helm` charts, `4.3.0` through `4.8.0` | Default. Any normal install. |
| Apache JFrog (legacy) | `https://apache.jfrog.io/artifactory/skywalking-helm` | Released charts `4.3.0` and older only — frozen, no new releases | You are pinned to an old chart and cannot move yet. |
| ghcr.io (OCI) | `oci://ghcr.io/apache/skywalking-helm/skywalking-helm` | Snapshot of every commit on `master`, versioned `0.0.0-<commit-sha>` | Testing an unreleased fix. |
| Source tree | `git clone` + `helm dep up chart/skywalking` | Your working copy of `chart/skywalking` | You are editing the chart. |

Chart version and SkyWalking version are separate things. Whichever source you use, the three
required values are always yours to set:

| value | current |
| --- | --- |
| `oap.image.tag` | `11.0.0` |
| `oap.storageType` | `elasticsearch`, `banyandb`, or `postgresql` |
| `ui.image.tag` | `horizon-1.0.0` |

## Released chart, Docker Hub OCI registry (>= 4.3.0)

The chart is pushed to Docker Hub as an OCI artifact (`make publish` runs
`helm push … oci://docker.io/apache`). There is no `helm repo add` step — an OCI
reference is the chart.

```shell
export SKYWALKING_RELEASE_VERSION=5.0.0
export SKYWALKING_RELEASE_NAME=skywalking
export SKYWALKING_RELEASE_NAMESPACE=default

helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://docker.io/apache/skywalking-helm \
  --version "${SKYWALKING_RELEASE_VERSION}" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

An OCI registry cannot be added with `helm repo add`, so `helm search repo` will not list the
available chart versions — pick and pin `--version` deliberately. To inspect or vendor a version
before installing:

```shell
helm show values oci://docker.io/apache/skywalking-helm --version 5.0.0
helm pull oci://docker.io/apache/skywalking-helm --version 5.0.0
```

The registry holds `4.3.0`, `4.4.0`, `4.5.0`, `4.6.0`, `4.7.0` and `4.8.0`. `4.9.0` is a released
version that never reached it, and `5.0.0` arrives when the release workflow publishes the tag — see
[Package and Publish a Release](../contributing/release.md). A version that is not there fails with
`FetchReference ... not found`.

With the default `elasticsearch.enabled=true`, the ECK CRDs must already exist in the cluster before
this install runs — the release contains an `Elasticsearch` custom resource, so the CRD cannot be
created by the same release. Install the `eck-operator-crds` chart as its own release first
(`helm install eck-crds eck-operator-crds --repo https://helm.elastic.co --version 3.3.1`), then
install with `--set eck-operator.installCRDs=false` (its default is `true`) so the two releases do
not both own the CRDs. Both steps are in [Elasticsearch](../storage/elasticsearch.md).

## Apache JFrog Helm repository (<= 4.3.0)

The classic (non-OCI) repository. It holds releases up to `4.3.0` and receives nothing new; it is
listed here only so old runbooks resolve.

```shell
helm repo add skywalking https://apache.jfrog.io/artifactory/skywalking-helm
helm repo update
helm search repo skywalking/skywalking --versions
```

The chart was named `skywalking` back then (it was renamed to `skywalking-helm` after `4.3.0`), so
the repo-qualified name is `skywalking/skywalking`.

Everything from `4.3.0` on comes from the Docker Hub OCI address above, except `4.9.0` — released
to `dist.apache.org`, never pushed to the registry.

## Development snapshots, ghcr.io

Every push to `master` packages `chart/skywalking` and pushes it to
`oci://ghcr.io/apache/skywalking-helm/skywalking-helm` from
`.github/workflows/publish-helm.yaml`, versioned `0.0.0-<full 40-character commit SHA>`. This repo
publishes exactly one chart, so that reference is the only snapshot address. Replace the SHA with
the revision you want to test.

```shell
helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://ghcr.io/apache/skywalking-helm/skywalking-helm \
  --version "0.0.0-3aee62ac0b0a8c9626abbd386e9728c859cd21be" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

These are snapshots of unreleased code. Use them to verify a fix, not to run production.

## From source

Clone, resolve the subcharts, then install from the local path.

```shell
git clone https://github.com/apache/skywalking-helm
cd skywalking-helm
helm dep up chart/skywalking

helm install "${SKYWALKING_RELEASE_NAME}" chart/skywalking \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

`helm dep up` is required before the first install and after any `Chart.yaml` change; it downloads
into `chart/skywalking/charts/` and writes `Chart.lock`. Each dependency declares its repository as
a URL, so no `helm repo add` is needed. What it pulls (these are **chart** versions, not image
versions — the BanyanDB server version is `banyandb.image.tag`, currently `0.11.0`):

| dependency | version | repository | condition |
| --- | --- | --- | --- |
| `eck-operator` | 3.3.1 | `https://helm.elastic.co/` | `elasticsearch.enabled` |
| `eck-elasticsearch` (alias `elasticsearch`) | 0.18.1 | `https://helm.elastic.co/` | `elasticsearch.enabled` |
| `postgresql` | 12.1.2 | `https://raw.githubusercontent.com/bitnami/charts/archive-full-index/bitnami` | `postgresql.enabled` |
| `skywalking-banyandb-helm` (alias `banyandb`) | 0.7.0 | `oci://docker.io/apache` | `banyandb.enabled` |

`make package` does the same `helm dep up` plus `helm package`, with `LICENSE` and `NOTICE` copied
into the chart directory first, and drops `skywalking-helm-5.0.0.tgz` in the repo root. `make clean`
removes the pulled subcharts, `Chart.lock` and the packaged tarball — **on Linux only**: the recipe
is one `rm` invocation whose `-rf` tokens land mid-argument-list, and BSD `rm` (macOS) stops option
parsing at the first operand, fails with `rm: bin/: is a directory` and leaves
`chart/skywalking/charts/` behind. See [Package and Publish a Release](../contributing/release.md).

## Next

- [Quick Start](quick-start.md) — a working install, end to end.
- [Version Compatibility](../evaluate/version-compatibility.md) — which OAP, UI and BanyanDB versions go together.
