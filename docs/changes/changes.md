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
- **`ui.config` is empty by default.** The chart now writes only the values it computes, as
  `${HORIZON_*:default}` tokens, and Horizon is configured by environment variable. A literal
  written into `ui.config` makes that field's `HORIZON_*` variable inert — see
  [Configure Horizon](../ui/configure.md).
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
- Documentation moved into `docs/` and is published at
  [skywalking.apache.org/docs/skywalking-helm](https://skywalking.apache.org/docs/skywalking-helm/next/readme/).

### Corrections

- Horizon UI does **not** refuse to start without configured users. It boots, serves the login
  page, and answers `/api/auth/health` with 200 — which is this chart's readiness probe — so the
  pod reports Ready and nobody can sign in. Earlier documentation claimed a `CrashLoopBackOff`.
  See [Set Up Logins](../ui/logins.md).
