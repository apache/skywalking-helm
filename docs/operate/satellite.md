# Satellite Gateway

[SkyWalking Satellite](https://skywalking.apache.org/docs/skywalking-satellite/latest/readme/) is an
optional lightweight gateway that sits in front of OAP: agents and Envoy send to Satellite, Satellite
buffers and load-balances into the OAP pods. This page covers turning it on in the chart, the ports it
exposes, repointing agents at it, and changing its settings.

## Enable it

Satellite is off by default (`satellite.enabled: false`) and its image tag has no default — set both:

```shell
helm upgrade --install "${SKYWALKING_RELEASE_NAME}" \
  oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false \
  --set satellite.enabled=true \
  --set satellite.image.tag=v1.3.0
```

The storage flags above are just the [Quick Start](../install/quick-start.md) ones — only the two
`satellite.*` flags are new. Keep whatever storage flags your release already uses; Satellite does
not care which backend OAP writes to.

`satellite.image.tag` is `required` in the template — leaving it unset fails the render with
`satellite.image.tag is required`. Pick a tag published for
`apache/skywalking-satellite` (default repository: `skywalking.docker.scarf.sh/apache/skywalking-satellite`);
the e2e tests instead run a CI build from `ghcr.io/apache/skywalking-satellite/skywalking-satellite`
(see `test/e2e/env`).

Enabling it renders five resources, all named `{fullname}-satellite`:

| Resource | Purpose |
| --- | --- |
| `Deployment` | `satellite.replicas` pods (default `1`) |
| `Service` | `satellite.service.type`, default `ClusterIP` |
| `ServiceAccount` | named `{fullname}-satellite`; `serviceAccounts.satellite` renames it |
| `Role` + `RoleBinding` | `get`/`watch`/`list` on `pods`, for OAP discovery |

`{fullname}` is `{release}-skywalking-helm` unless you set `fullnameOverride`. With
`--set fullnameOverride=skywalking` (what the e2e tests use) the Service is simply
`skywalking-satellite`.

## Ports

Container ports and Service ports are both generated from the `satellite.ports` map, so the key
becomes the port name:

| `satellite.ports.*` | Default | Purpose |
| --- | --- | --- |
| `grpc` | `11800` | agent/Envoy traffic in — this is the address agents use |
| `prometheus` | `1234` | Satellite's own Prometheus metrics |
| `pprof` | commented out (`6060`) | Go pprof, uncomment only for debugging |

Add any extra port by adding a key to the map; nothing else needs changing.

> The readiness probe is a TCP check against `oap.ports.grpc`, **not** `satellite.ports.grpc`. If you
> move Satellite's gRPC port without moving OAP's, the probe targets a port Satellite is not listening
> on and the pod never becomes Ready.

## Point agents at Satellite

Once Satellite is up, replace the OAP backend address in your agents and mesh config with the
Satellite Service on port `11800` — the port number is the same, only the host changes:

```properties
# Java agent — host is the Satellite Service, i.e. {fullname}-satellite.<namespace>
collector.backend_service=${SW_AGENT_COLLECTOR_BACKEND_SERVICES:skywalking-satellite.<namespace>:11800}
```

```shell
# Istio: send Envoy access logs to Satellite instead of OAP
istioctl install -y \
  --set meshConfig.defaultConfig.envoyAccessLogService.address=skywalking-satellite.istio-system:11800
```

Everything else — the UI, the OAP REST/admin endpoints, `swctl` — keeps talking to the OAP Service
directly. Satellite only fronts the gRPC ingestion path. See
[OAP Endpoints for Agents](../expose/oap-endpoints.md) for the endpoints Satellite does not front.

## How Satellite finds OAP

The chart wires Kubernetes-native discovery, so Satellite talks to OAP **pods** rather than the OAP
Service. These env vars are set by the template and should not be overridden:

| Env | Value |
| --- | --- |
| `SATELLITE_GRPC_CLIENT_FINDER` | `kubernetes` |
| `SATELLITE_GRPC_CLIENT_KUBERNETES_NAMESPACE` | the release namespace |
| `SATELLITE_GRPC_CLIENT_KUBERNETES_KIND` | `pod` |
| `SATELLITE_GRPC_CLIENT_KUBERNETES_SELECTOR_LABEL` | `app={release},release={release},component=oap` — the `app` label is the release name, not the chart name |
| `SATELLITE_GRPC_CLIENT_KUBERNETES_EXTRA_PORT` | `oap.ports.grpc` (`11800`) |

That is why the chart also creates the Role granting `pods` read access, and the RoleBinding that
grants it to whatever `skywalking.serviceAccountName.satellite` resolves to — so renaming the account
with `serviceAccounts.satellite` keeps the permission. The chart always *creates* that
ServiceAccount, so `serviceAccounts.satellite` is a rename, not a way to adopt a ServiceAccount that
already exists (Helm would fail on the conflict).

## Change Satellite settings

Entries in the `satellite.env` map are rendered after the built-ins above, so they can override
anything the shipped config reads from the environment — which is almost every setting, because
`satellite_config.yaml` writes each one as an `${ENV:default}` placeholder (`logger.level` from
`SATELLITE_LOGGER_LEVEL`, `telemetry.prometheus.address` from
`SATELLITE_TELEMETRY_PROMETHEUS_ADDRESS`, and so on):

```shell
--set satellite.env.SATELLITE_LOGGER_LEVEL=debug
```

The full placeholder list is in
[Override settings](https://skywalking.apache.org/docs/skywalking-satellite/latest/en/setup/configuration/override-settings/)
upstream.

### The `satellite.config` map

`satellite.config` is a map of file name to file content. Each key is written into the
`{fullname}-satellite-cm-override` ConfigMap and mounted with `subPath` at
`/skywalking/config/<key>`; a nested map becomes a directory, so `config.<dir>.<file>` mounts at
`/skywalking/config/<dir>/<file>`.

> The Satellite image loads its configuration from `/skywalking/configs/satellite_config.yaml` —
> `configs`, plural — and the chart passes no `--config` argument to change that. A
> `satellite.config` key named `satellite_config.yaml` therefore lands at
> `/skywalking/config/satellite_config.yaml`, *beside* the shipped file rather than over it, and has
> no effect. Do not use `satellite.config` to rewrite the pipeline; use `satellite.env`, or bake a
> custom image.

## Related

- [Configure OAP](oap-configuration.md) — the same `env` map on the OAP side, where `oap.config`
  *does* mount over the shipped files (the OAP image reads `/skywalking/config`, singular)
- [Scaling and the OAP Cluster](scaling.md)
- [Chart values reference](../reference/skywalking-chart-values.md)
