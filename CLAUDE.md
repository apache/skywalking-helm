# CLAUDE.md

## Project Overview

Apache SkyWalking Helm Charts — Helm 3 charts for deploying SkyWalking and related components on Kubernetes.

## Repository Structure

```
chart/
  skywalking/          # Main SkyWalking chart (OAP, UI, Satellite)
    Chart.yaml         # Chart metadata and dependencies
    values.yaml        # Default values
    values-my-es.yaml  # Example values for external Elasticsearch
    templates/
      _helpers.tpl     # Shared template helpers (naming, env vars, init containers)
      oap-*.yaml       # OAP server templates
      ui-*.yaml        # UI templates
      satellite-*.yaml # Satellite templates
      NOTES.txt        # Post-install notes
  adapter/             # SWCK Adapter chart
  operator/            # SWCK Operator chart
test/e2e/              # E2E test configs (skywalking-infra-e2e format)
  e2e-elasticsearch.yaml
  e2e-banyandb-*.yaml
  values.yaml          # Test-specific value overrides
  swck/                # SWCK-specific e2e tests
.github/workflows/
  e2e.ci.yaml          # CI pipeline running all e2e tests
```

## Chart Dependencies

Defined in `chart/skywalking/Chart.yaml`:
- **eck-operator** (3.3.1) — ECK operator, condition: `eckOperator.enabled`
- **eck-elasticsearch** (0.18.1, alias: `elasticsearch`) — ECK-managed ES, condition: `elasticsearch.enabled`
- **postgresql** (12.1.2) — Bitnami PostgreSQL, condition: `postgresql.enabled`
- **skywalking-banyandb-helm** (alias: `banyandb`) — BanyanDB, condition: `banyandb.enabled`

## Key Conventions

### Template Helpers (`_helpers.tpl`)
- `skywalking.fullname` — base name for all resources
- `skywalking.oap.fullname` / `skywalking.ui.fullname` / `skywalking.satellite.fullname` — component names
- `skywalking.elasticsearch.fullname` — ECK Elasticsearch resource name (service is `{name}-es-http`)
- `skywalking.containers.wait-for-storage` — init container that waits for the configured storage backend
- `skywalking.oap.envs.storage` — storage-specific environment variables for OAP

### Storage Pattern
Each storage backend (elasticsearch, postgresql, banyandb) follows the same pattern:
- `*.enabled` — deploy the backend as a subchart
- `*.config.*` — connection settings for external instances (when `enabled: false`)
- `_helpers.tpl` handles both embedded and external modes in `wait-for-storage` and `oap.envs.storage`

### ECK Elasticsearch
- ECK auto-generates an auth secret: `{fullname}-es-elastic-user` with key `elastic`
- HTTP TLS is disabled by default (`http.tls.selfSignedCertificate.disabled: true`) for OAP connectivity
- Node topology is configured via `elasticsearch.nodeSets[]` (count, config, podTemplate, volumeClaimTemplates)

## Common Commands

```shell
# Update chart dependencies
helm dep up chart/skywalking

# Template rendering (for validation)
helm template test chart/skywalking \
  --set oap.image.tag=10.3.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=10.3.0

# Template with external ES (no ECK)
helm template test chart/skywalking \
  --set oap.image.tag=10.3.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=10.3.0 \
  --set elasticsearch.enabled=false \
  --set eckOperator.enabled=false

# Package chart
make package

# Clean build artifacts
make clean
```

## Required Values

These must be set explicitly for any deployment:
- `oap.image.tag`
- `oap.storageType` (`elasticsearch`, `postgresql`, or `banyandb`)
- `ui.image.tag`

## E2E Tests

Tests use [skywalking-infra-e2e](https://github.com/apache/skywalking-infra-e2e). Each `.yaml` file under `test/e2e/` defines setup steps, triggers, and verification queries. The CI workflow is in `.github/workflows/e2e.ci.yaml`.

## Docs to Keep in Sync

When modifying chart configuration, update all of:
1. `chart/skywalking/values.yaml` — default values
2. `chart/skywalking/README.md` — parameter tables
3. `README.md` — install examples and user-facing docs
4. `chart/skywalking/values-my-es.yaml` — external ES example (if ES-related)
5. `test/e2e/values.yaml` — test overrides (if defaults change)

## Git Workflow

- **Do not push directly to master.** Always create a feature branch and open a PR.
- Branch naming example: `upgrade-elasticsearch-eck-8.18.8`
- **Do not add Claude as co-author** in commit messages.

## License

All files must include the Apache 2.0 license header.
