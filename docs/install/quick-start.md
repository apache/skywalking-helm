# Quick Start

The shortest path from an empty Kubernetes cluster to a running SkyWalking install: OAP 11.0.0
with Elasticsearch storage and Horizon UI 1.0.0, reachable in your browser.

## Before you start

- A Kubernetes cluster and a working `kubectl` context.
- Helm 3.8 or newer (the OCI install below needs a Helm that can pull `oci://` charts).
- `oap.storageType` has no default and must be set, but `elasticsearch.enabled` defaults to `true`,
  so the chart deploys Elasticsearch through [ECK](https://github.com/elastic/cloud-on-k8s) as a
  **3-node** cluster (`elasticsearch.nodeSets[0].count: 3`, `elasticsearch.version: 8.18.8`).
  See [Requirements](../evaluate/requirements.md) for sizing, and
  [Pick a Storage Backend](../storage/choose-a-backend.md) if you would rather start with BanyanDB.

## 1. Set the release variables

```shell
export SKYWALKING_RELEASE_VERSION=5.0.0
export SKYWALKING_RELEASE_NAME=skywalking
export SKYWALKING_RELEASE_NAMESPACE=default
```

## 2. Install the ECK CRDs

Helm renders the chart's `Elasticsearch` custom resource during install, so the ECK CRDs must
already exist in the cluster. Install them as their own release — the version matches the
`eck-operator` dependency pinned in `chart/skywalking/Chart.yaml`:

```shell
helm install eck-crds eck-operator-crds \
  --repo https://helm.elastic.co --version 3.3.1 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" --create-namespace
```

Then pass `--set eck-operator.installCRDs=false` when installing SkyWalking so the two releases do
not both own the CRDs.

> Skip this step entirely if you set `elasticsearch.enabled=false` — using an external
> Elasticsearch, BanyanDB, or PostgreSQL needs no CRDs.

## 3. Install the chart

```shell
helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version "${SKYWALKING_RELEASE_VERSION}" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false
```

The three values that have no default and must always be set:

| value | this install | notes |
| --- | --- | --- |
| `oap.image.tag` | `11.0.0` | OAP server image tag |
| `oap.storageType` | `elasticsearch` | also `banyandb`, `postgresql` |
| `ui.image.tag` | `horizon-1.0.0` | must be a `horizon-*` tag |

Other chart sources — Apache JFrog, ghcr.io snapshots, a local clone — are covered in
[Where to Get the Chart](../install/chart-sources.md).

## 4. Wait for it to come up

```shell
kubectl get pods -n "${SKYWALKING_RELEASE_NAMESPACE}" -w
```

A one-shot `*-oap-init-*` Job creates the storage schema; the OAP Deployment runs in `-Dmode=no-init`
and stays un-Ready until that Job finishes. Both run in the main install phase, so you can add
`--wait --wait-for-jobs` to the `helm install` above and let Helm block instead (the extra
`--wait-for-jobs` makes Helm surface an init-Job failure directly). To watch the Job:

```shell
kubectl get job -n "${SKYWALKING_RELEASE_NAMESPACE}" -l release="${SKYWALKING_RELEASE_NAME}"
kubectl logs -n "${SKYWALKING_RELEASE_NAMESPACE}" job/<oap-init-job-name> -f
```

Details in [The OAP Init Job](../operate/oap-init-job.md); failures in
[Install and Startup Failures](../troubleshooting/install-and-startup.md).

## 5. Reach the UI

The UI Service is `ClusterIP` on port `80` (targeting the BFF's port `8081`). Its name is
`<release>-skywalking-helm-ui`, because the chart is named `skywalking-helm`:

```shell
kubectl port-forward -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  svc/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui 8080:80
open http://127.0.0.1:8080
```

> Prefer shorter resource names? Add `--set fullnameOverride=skywalking` at install time and the
> Service becomes `skywalking-ui`.

For a `NodePort`, `LoadBalancer` or Ingress instead of port-forwarding, see
[UI Service and Ingress](../expose/ui-service-and-ingress.md).

## 6. Create a login — the install has none

Horizon UI has **no** built-in `admin/admin` account, and this chart configures no users. The BFF
does not fail closed: it boots, serves the login page, and passes its readiness probe, so the pod
reports Ready and nobody can log in.

Go to [Set Up Logins](../ui/logins.md) for a copy-pastable demo user and the production
Secret-backed pattern. Do this before you rely on the deployment.

## Uninstall

```shell
helm uninstall "${SKYWALKING_RELEASE_NAME}" -n "${SKYWALKING_RELEASE_NAMESPACE}"
helm uninstall eck-crds -n "${SKYWALKING_RELEASE_NAMESPACE}"
```

## Next steps

- [Set Up Logins](../ui/logins.md) — required before anyone can use the UI.
- [OAP Endpoints for Agents](../expose/oap-endpoints.md) — point agents at gRPC `11800` / HTTP `12800`.
- [Pick a Storage Backend](../storage/choose-a-backend.md) — Elasticsearch vs BanyanDB vs PostgreSQL.
- [Configure OAP](../operate/oap-configuration.md) — environment variables and config overrides.
