# Apache SkyWalking Helm Chart

A Helm 3 chart for running Apache SkyWalking on Kubernetes: the OAP backend, the Horizon UI web
console, an optional Satellite gateway, and a storage backend the chart can deploy for you.

This repository ships one chart, `chart/skywalking` — OAP, Horizon UI, optional Satellite, optional
storage (Elasticsearch, PostgreSQL, BanyanDB). The [SWCK](https://github.com/apache/skywalking-swck)
operator and its custom-metrics adapter live in `apache/skywalking-swck`, where the operator, its
CRDs and its image are developed and released.

## Start here

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0
```

`oap.image.tag`, `oap.storageType` and `ui.image.tag` have no defaults and must be given on every
install; `banyandb.image.tag` is required on top of those whenever `banyandb.enabled=true` — it is a
tag, not an image reference: `0.11.0`, published on `docker.io/apache/skywalking-banyandb`. Read
[Quick Start](install/quick-start.md) for the full path, including the ECK CRD step you need
whenever `elasticsearch.enabled` is left at its default `true`.

**A fresh install has no login.** Horizon UI ships no default credentials and does not fail closed —
the pod reports Ready and nobody can sign in until you configure users. See
[Set Up Logins](ui/logins.md).

## Find your way

- **Deciding whether this fits** — [What This Chart Deploys](evaluate/what-this-chart-deploys.md),
  [Requirements](evaluate/requirements.md),
  [Version Compatibility](evaluate/version-compatibility.md)
- **Installing** — [Quick Start](install/quick-start.md),
  [Where to Get the Chart](install/chart-sources.md)
- **Storage** — [Pick a Storage Backend](storage/choose-a-backend.md), then
  [Elasticsearch](storage/elasticsearch.md), [BanyanDB](storage/banyandb.md) or
  [PostgreSQL](storage/postgresql.md)
- **The web UI** — [Horizon UI in This Chart](ui/horizon-ui.md),
  [Set Up Logins](ui/logins.md), [Configure Horizon](ui/configure.md)
- **Exposing it** — [UI Service and Ingress](expose/ui-service-and-ingress.md),
  [TLS](expose/tls.md), [OAP Endpoints for Agents](expose/oap-endpoints.md)
- **Running it** — [The OAP Init Job](operate/oap-init-job.md),
  [Configure OAP](operate/oap-configuration.md),
  [Scaling and the OAP Cluster](operate/scaling.md),
  [Satellite Gateway](operate/satellite.md)
- **Upgrading** — [Upgrade](upgrade/upgrading.md)
- **When it breaks** — [Install and Startup Failures](troubleshooting/install-and-startup.md),
  [UI and Login Problems](troubleshooting/ui-and-login.md)
- **Every value** — [Chart Values](reference/skywalking-chart-values.md)
- **Contributing** — [Run the E2E Tests](contributing/e2e-tests.md),
  [Package and Publish a Release](contributing/release.md)
- **What changed** — [Changelog](changes/changes.md), and the [5.0.0 release notes](changes/changes-5.0.0.md)

## Related documentation

- [SkyWalking backend setup](https://skywalking.apache.org/docs/main/latest/en/setup/backend/backend-setup/)
- [OAP configuration vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/)
- [Horizon UI `horizon.yaml` reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md)
- [BanyanDB Helm chart](https://github.com/apache/skywalking-banyandb-helm)
