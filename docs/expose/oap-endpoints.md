# OAP Endpoints for Agents

Which OAP ports this chart opens, how to open more (Zipkin, PromQL, LogQL, TraceQL, self-telemetry), and what agents, `swctl` and Grafana should point at.

## One map drives everything

`chart/skywalking/templates/oap-svc.yaml` turns every key in `oap.ports` into a Service port:

```yaml
  ports:
  {{- range $key, $value :=  .Values.oap.ports }}
  - port: {{ $value }}
    name: {{ $key }}
  {{- end }}
```

`oap-deployment.yaml` ranges over the same map for `containerPort`. So **adding a key to `oap.ports` is how you expose a port** — there is no separate switch. The Service has no `targetPort`, so the Service port and the container port are always the same number.

The Service is named `<fullname>-oap`, type `ClusterIP` by default. The chart is named `skywalking-helm`, so `helm install skywalking ...` renders `skywalking-skywalking-helm-oap`; add `--set fullnameOverride=skywalking` (what the e2e tests do) to get a plain `skywalking-oap`:

```shell
helm dep up chart/skywalking
helm template skywalking chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set ui.image.tag=horizon-1.0.0 \
  -s templates/oap-svc.yaml
```

## The ports

| Key | Default | Serves | In `oap.ports` by default | Needs OAP env too |
|---|---|---|---|---|
| `grpc` | `11800` | Native agent protocol (traces, JVM/meters, profiling, logs, events). Every other gRPC receiver — OTLP, Envoy ALS, Rover eBPF, Satellite forwarding — shares it, because `SW_RECEIVER_GRPC_PORT` defaults to `0` (fall back to the core gRPC server) | yes | no |
| `rest` | `12800` | GraphQL query API at `/graphql` (Horizon's `oap.queryUrl`, `swctl`). HTTP receivers share it for the same reason (`SW_RECEIVER_SHARING_REST_PORT:0`). All three pod probes `tcpSocket` this port | yes | no |
| `admin` | `17128` | admin-server: `/status/*`, `/debugging/*`, inspect, dsl-debugging, runtime-rule, and the `ui-management` template store Horizon uses when `ui.config.templates.mode` is `live`. Wired into Horizon as `oap.adminUrl` | yes | no |
| `zipkin-receiver` | `9411` | Zipkin span ingestion, `POST /api/v2/spans` | no | no — the chart sets `SW_RECEIVER_ZIPKIN=default` and `SW_RECEIVER_ZIPKIN_REST_PORT` for you |
| `zipkin-query` | `9412` | Zipkin query API under `/zipkin` (Zipkin-Lens compatible). Also makes the chart write Horizon's `oap.zipkinUrl` | no | no — the chart sets `SW_QUERY_ZIPKIN=default` and `SW_QUERY_ZIPKIN_REST_PORT` |
| `promql` | `9090` | Prometheus-compatible query API (Grafana datasource) | no | no — the `promql` module is on by default in OAP 11 |
| `logql` | `3100` | Loki-compatible log query API | no | no — the `logql` module is on by default in OAP 11 |
| `traceql` | `3200` | Tempo-compatible trace query API | no | **yes** — `SW_TRACEQL` defaults to empty (module off) |
| `metrics` | `1234` | OAP self-telemetry, Prometheus exposition for scraping | no | no — `SW_TELEMETRY` defaults to `prometheus` on `1234` |
| `zabbix` | `10051` | Zabbix receiver (the example line in `values.yaml`) | no | **yes** — `SW_RECEIVER_ZABBIX` defaults to empty |

"In `oap.ports` by default" means the chart publishes the Service/container port. The last column is about OAP itself: a port that is published but whose module is off answers nothing.

`admin: 17128` is required for OAP 11 and is what Horizon's admin calls go to. Set it to `null` on any OAP 10.x release: `admin-server` first appears in OAP 11, and on 10.x port 17128 is the AI-pipeline URI-recognition server.

## Opening more ports

Uncomment the lines already present in `values.yaml`, or pass them on the command line:

```shell
helm install skywalking oci://docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set ui.image.tag=horizon-1.0.0 \
  --set oap.ports.zipkin-receiver=9411 \
  --set oap.ports.zipkin-query=9412
```

For a module that is off in OAP, add the port *and* the env — `oap.env` values are rendered quoted, so booleans are safe:

```yaml
oap:
  ports:
    grpc: 11800
    rest: 12800
    admin: 17128
    traceql: 3200
    metrics: 1234
  env:
    SW_TRACEQL: default
    SW_TRACEQL_ENABLE_DATASOURCE_SKYWALKING: true
```

Port names are Kubernetes port names: lowercase, `[a-z0-9-]`, 15 characters max (`zipkin-receiver` is exactly 15).

### Do not renumber `grpc` / `rest` / `admin` on their own

The chart feeds `oap.ports` to Kubernetes, not to OAP — for these three it never sets the matching `SW_*` variable. OAP keeps binding `SW_CORE_GRPC_PORT:11800`, `SW_CORE_REST_PORT:12800` and `SW_ADMIN_SERVER_PORT:17128`, so changing only the value gives you a Service pointing at a closed port. If you must move one, change all of it:

```yaml
oap:
  ports:
    rest: 12801
  env:
    SW_CORE_REST_PORT: 12801
  livenessProbe:
    tcpSocket: { port: 12801 }
    initialDelaySeconds: 5
    periodSeconds: 10
  readinessProbe:
    tcpSocket: { port: 12801 }
    initialDelaySeconds: 5
    periodSeconds: 10
  startupProbe:
    tcpSocket: { port: 12801 }
    failureThreshold: 30
    periodSeconds: 10
```

The default probes hardcode `12800`; leaving them behind makes the pod restart-loop. Horizon needs no change either way — the UI ConfigMap renders `oap.queryUrl` / `oap.adminUrl` from `oap.ports.rest` / `oap.ports.admin`. `zipkin-receiver` and `zipkin-query` have no such problem — the chart derives their env from the value.

## What to point at what

Assuming release `skywalking` in namespace `skywalking`, installed with `--set fullnameOverride=skywalking` so the Service is `skywalking-oap`. Without that override the name is `skywalking-skywalking-helm-oap` — substitute it everywhere below.

| Client | Address |
|---|---|
| Java / Go / Python / Node.js / Rust / nginx-lua agents | `skywalking-oap.skywalking.svc:11800` (gRPC, no scheme) |
| OTLP, Envoy ALS, Rover eBPF | the same `:11800` |
| Browser and other HTTP reporters | `http://skywalking-oap.skywalking.svc:12800` |
| `swctl` | `--base-url=http://skywalking-oap.skywalking.svc:12800/graphql` |
| Horizon UI | wired by the chart: query `:12800`, admin `:17128` |
| Zipkin senders | `http://skywalking-oap.skywalking.svc:9411/api/v2/spans` |
| Grafana (Prometheus / Loki datasource) | `http://skywalking-oap.skywalking.svc:9090`, `:3100` |
| Prometheus scrape of OAP itself | `skywalking-oap.skywalking.svc:1234` |

Java agent example:

```shell
-Dskywalking.collector.backend_service=skywalking-oap.skywalking.svc:11800
```

Horizon does **not** proxy `/graphql` to OAP, so anything that used to query through the UI must talk to the OAP Service directly on `12800`.

If [Satellite](../operate/satellite.md) is enabled, agents point at the Satellite Service on `11800` instead and Satellite forwards to OAP.

## Reaching OAP from outside the cluster

The chart ships no Ingress for OAP — only the UI has one (see [UI Service and Ingress](ui-service-and-ingress.md)). Options:

```shell
# one laptop, temporary
kubectl port-forward -n skywalking svc/skywalking-oap 12800:12800
```

```yaml
# agents outside the cluster
oap:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

`oap.service.type` accepts any Service type (`ClusterIP`, `NodePort`, `LoadBalancer`) and `oap.service.annotations` is passed straight through to the Service metadata. The agent protocol on `11800` is gRPC over HTTP/2, so an L7 HTTP ingress will not do — use an L4 / NLB Service or a gRPC-aware gateway.

A public OAP Service publishes **every** key in `oap.ports`, and `admin: 17128` is one of them by default — it serves `/status/*`, `/debugging/*`, inspect and the runtime-rule write APIs. Front the public address with something that forwards only `11800` / `12800` rather than dropping `admin` from `oap.ports`: the UI ConfigMap still renders `oap.adminUrl` as `:17128`, so removing the port breaks Horizon. See [TLS](tls.md) before putting any of these on the internet.

## Related

- [Configure OAP](../operate/oap-configuration.md) — `oap.env`, `oap.config`, dynamic configuration
- [Satellite Gateway](../operate/satellite.md)
- [skywalking Chart values](../reference/skywalking-chart-values.md)
- [OAP Configuration Vocabulary](https://skywalking.apache.org/docs/main/latest/en/setup/backend/configuration-vocabulary/) — every `SW_*` variable and its default
