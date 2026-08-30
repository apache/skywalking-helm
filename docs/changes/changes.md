# Changelog

## 5.0.0

Targets SkyWalking OAP 11.0.0, Horizon UI 1.0.0 and BanyanDB 0.11.0. See
[Upgrade](../upgrade/upgrading.md) for the migration steps.

### Breaking changes

- **OAP 11 requires BanyanDB 0.11.x.** OAP pins the BanyanDB server API versions it accepts
  (`SW_STORAGE_BANYANDB_COMPATIBLE_SERVER_API_VERSIONS`, `0.11` in 11.0.0) and checks them with
  string equality, so pairing OAP 11 with BanyanDB 0.10.x makes OAP refuse to start. The three
  versions move together — see [Version Compatibility](../evaluate/version-compatibility.md).
- **`oap.ports.admin` is required.** OAP 11 enables every admin feature module by default and
  serves `/status/*` and `/debugging/*` on the admin port only; they are no longer mirrored on
  `oap.ports.rest`. Horizon UI reads status, inspect, DSL debugging and the dashboard template
  store from it.
- **The legacy booster UI is no longer supported.** OAP 11 deleted `apm-webapp` and the
  `skywalking-booster-ui` submodule along with the `docker.ui` build target, so
  `apache/skywalking-ui` publishes no `11.x` tag — only `horizon-*` tags. Replace
  `ui.image.tag=<oap-version>` with `ui.image.tag=horizon-1.0.0`.
- **`oap.config.ui-initialized-templates` does nothing.** OAP 11 removed the on-disk dashboard
  seed files and `UITemplateInitializer`, along with the sidebar menu storage, the
  `UIConfigurationManagement` GraphQL mutations and `SW_ENABLE_UPDATE_UI_TEMPLATE`. Horizon UI
  ships its own dashboard library and manages templates over the admin REST port.
- **Horizon is configured by environment variable, and no ConfigMap is mounted by default.** The
  image ships a complete env-tokenized `/app/horizon.yaml`; the chart sets only what it computes
  (`HORIZON_SERVER_PORT`, `HORIZON_OAP_QUERY_URL`, and the admin, Zipkin and public URLs when
  configured) and leaves the rest to `ui.extraEnv` / `ui.envFromSecret`. `ui.config` is now opt-in:
  setting it renders a ConfigMap and mounts it *over* the image's file, so fields you do not write
  fall back to Horizon's defaults. If you carried a `ui.config` block from the pre-release `main`
  values, move it to environment variables — see [Configure Horizon](../ui/configure.md).
- **The SWCK charts are removed.** `chart/operator` and `chart/adapter` packaged
  [apache/skywalking-swck](https://github.com/apache/skywalking-swck) — its image, its CRDs and its
  version — and had no relationship to `chart/skywalking`. They were never released to Docker Hub,
  so no released artifact disappears, but installs from source or from the `ghcr.io` snapshot
  channel will break. They belong with the operator, where the CRDs are generated alongside the
  code that consumes them.
- **The UI no longer proxies `/graphql`.** Callers that talked to the UI's GraphQL endpoint
  (for example `swctl --base-url=http://<ui>/graphql`) must target the OAP service directly on
  `oap.ports.rest`.

### Features

- `ui.extraVolumes` / `ui.extraVolumeMounts`, for the two Horizon settings that take a filesystem
  path: `auth.tokensFile` and `sourceMaps.bootMountDir`.
- `server.publicUrl` is derived from the first `ui.ingress.hosts` entry when an ingress is enabled,
  so single sign-on callbacks and the OAuth issuer are built from the address operators actually
  reach — see [UI Service and Ingress](../expose/ui-service-and-ingress.md).
- `server.port` is derived from `ui.service.internalPort`, so the BFF binds the port the container
  exposes.
- `oap.extraEnv` (a list, so entries can carry `valueFrom`) and `oap.envFromSecret`, applied to the
  OAP Deployment and the init Job. Note Kubernetes gives an explicit `env` entry precedence over
  `envFrom`, and the chart sets `SW_ES_PASSWORD` / `SW_DATA_SOURCE_PASSWORD` itself — so sourcing
  those from a Secret needs `oap.extraEnv`.
- Horizon's config hot-reload works again. The chart previously mounted `horizon.yaml` with
  `subPath`, which Kubernetes never updates in place, so the file watcher could not fire.
- `tools/releasing/release.sh` and `release-passed.sh`, plus
  [the release guide](../contributing/release.md) — the Apache process was previously unwritten.
- The E2E suite is rebuilt around Horizon: every assertion runs through the UI's API rather than
  OAP's GraphQL, so it exercises the path the chart is responsible for wiring.
- Documentation moved into `docs/` and is published at
  [skywalking.apache.org/docs/skywalking-helm](https://skywalking.apache.org/docs/skywalking-helm/next/readme/).

### Corrections

- Horizon UI does **not** refuse to start without configured users. It boots, serves the login
  page, and answers `/api/auth/health` with 200 — which is this chart's readiness probe — so the
  pod reports Ready and nobody can sign in. Earlier documentation claimed a `CrashLoopBackOff`.
  See [Set Up Logins](../ui/logins.md).
