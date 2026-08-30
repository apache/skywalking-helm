# UI Service and Ingress

How to reach the Horizon UI that this chart deploys: the Service it creates, the four ways to get traffic to it, and what changes in Horizon's own config once you put an Ingress in front.

## The Service

`templates/ui-svc.yaml` creates one Service named `<release>-<chart>-ui`, selecting the UI pod. It maps `ui.service.externalPort` → `ui.service.internalPort`:

```yaml
ui:
  service:
    type: ClusterIP
    externalPort: 80    # the port on the Service
    internalPort: 8081  # the port the Horizon BFF binds
```

`internalPort` is load-bearing in four places at once — the Service `targetPort`, the container's `containerPort` (named `page`), `server.port` in the generated `horizon.yaml`, and both probes, which target the `page` port by name. Change it and all four move together.

| Value | Default | Notes |
|---|---|---|
| `ui.service.type` | `ClusterIP` | `ClusterIP`, `NodePort` or `LoadBalancer` |
| `ui.service.externalPort` | `80` | Service port; also the Ingress backend port |
| `ui.service.internalPort` | `8081` | Horizon BFF listen port |
| `ui.service.clusterIP` | unset | Only applied when `type: ClusterIP` |
| `ui.service.nodePort` | unset | Only applied when `type: NodePort`; auto-allocated if unset |
| `ui.service.loadBalancerIP` | unset | Rendered whenever set — the template does not check the type |
| `ui.service.loadBalancerSourceRanges` | unset | List of CIDRs |
| `ui.service.externalIPs` | unset | List of IPs |
| `ui.service.annotations` | `{}` | e.g. cloud load-balancer / TLS-cert annotations |
| `ui.service.portName` | unset | The Service port is unnamed unless you set this |

Setting `ui.enabled: false` skips the Deployment, Service, Ingress, ConfigMap and PVC entirely — nothing on this page applies then.

## Reaching the UI without an Ingress

```shell
# ClusterIP (default) — port-forward
kubectl port-forward svc/<release>-skywalking-helm-ui 8080:80 -n <namespace>
# then open http://127.0.0.1:8080

# NodePort
kubectl get svc <release>-skywalking-helm-ui -n <namespace> \
  -o jsonpath='{.spec.ports[0].nodePort}'

# LoadBalancer
kubectl get svc <release>-skywalking-helm-ui -n <namespace> \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

`helm status <release>` prints the same commands, filled in for your release.

Note that the UI does **not** proxy `/graphql` to OAP. Tools like `swctl` must talk to the OAP Service directly — see [OAP Endpoints for Agents](oap-endpoints.md).

## The Ingress

```yaml
ui:
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
    hosts:
      - skywalking.example.com
    tls:
      - secretName: skywalking-tls
        hosts:
          - skywalking.example.com
```

Renders one Ingress named `<release>-<chart>-ui`, one rule per `hosts` entry, backed by the UI Service on `ui.service.externalPort`.

Three things to know:

- **The path comes from the host entry, not from `ui.ingress.path`.** Each entry is split on `/`: `skywalking.example.com` gives path `/`, and `skywalking.example.com/ui` gives host `skywalking.example.com` with path `/ui` (`pathType: Prefix`). `ui.ingress.path` is only used in the post-install `helm status` output — it does not reach the Ingress object.
- **There is no `ingressClassName` field.** Select a controller with the `kubernetes.io/ingress.class` annotation under `ui.ingress.annotations`.
- **The API version is picked from the cluster** — `networking.k8s.io/v1`, else `v1beta1`, else `extensions/v1beta1`. Offline `helm template` has no cluster to ask and falls back to `extensions/v1beta1`; add `--api-versions networking.k8s.io/v1/Ingress` when rendering locally to see what a modern cluster gets.

## Enabling the Ingress rewrites `server.publicUrl`

When `ui.ingress.enabled` is true **and** `ui.ingress.hosts` is non-empty, `templates/ui-configmap.yaml` adds `server.publicUrl` to the generated `horizon.yaml`, built from the **first** host entry — scheme `https` when `ui.ingress.tls` is non-empty, `http` otherwise:

```yaml
# rendered horizon.yaml, with hosts: [skywalking.example.com] and a tls entry
server:
  port: 8081
  publicUrl: ${HORIZON_PUBLIC_URL:https://skywalking.example.com}
```

Why the chart bothers: with `publicUrl` blank, Horizon derives its public base URL **per request**, from whatever `Host` and scheme reached the BFF. Behind an ingress that terminates TLS and rewrites `Host`, that is the internal address — so SSO redirect/callback URLs and the OAuth issuer Horizon advertises point at a hostname the browser and the identity provider cannot use. Pinning it once at deploy time makes those stable.

Details worth knowing:

- The host entry is used **verbatim**, path included: `hosts: [skywalking.example.com/ui]` yields `publicUrl: http://skywalking.example.com/ui`.
- The scheme is decided by `ui.ingress.tls` alone. TLS terminated further out (a cloud LB in front of an ingress with no `tls:` block) still renders `http://` — set the value yourself in that case.
- It is written as a `${HORIZON_PUBLIC_URL:...}` token, so the derived value is only a default: `ui.extraEnv`/`ui.envFromSecret` can still override it at runtime.
- To pin it in the chart instead, set `ui.config.server.publicUrl` — a literal there wins over the derived default, and makes `HORIZON_PUBLIC_URL` inert. See [Configure Horizon](../ui/configure.md).

Also set `ui.config.session.cookieSecure: true` when you serve the UI over HTTPS, so the session cookie is not sent in the clear. The `HORIZON_SESSION_COOKIE_SECURE` env var will not do it — the chart's `horizon.yaml` omits the `session:` block, so there is no token to expand. See [TLS](tls.md).

## `server.trustProxy` and the client address

Horizon's login audit records the client address of each attempt. Behind an ingress every request arrives from the proxy, so without `trustProxy` the audit records the ingress address for everyone.

```yaml
ui:
  config:
    server:
      trustProxy: 1     # one proxy hop in front of the BFF
```

Accepted forms are a **hop count** (`1` = one proxy in front, `2` = a proxy behind a proxy) or the ingress **address / CIDR** (e.g. `10.0.0.0/8`, comma-separated for several).

`true` is **refused at boot** — the pod will not start. Blanket trust would let any caller set `X-Forwarded-For` and choose the address written to the audit log, so Horizon requires you to name how far the trust extends. Pick the hop count or CIDR that matches your actual topology; too large a hop count has the same problem as `true`.

Set it in `ui.config`, not via `ui.extraEnv`. `HORIZON_TRUST_PROXY` is inert under this chart: the generated `horizon.yaml` has no `server.trustProxy` line, so there is no `${...}` token for Horizon to expand and the schema default (`false`) wins. Write `trustProxy: "${HORIZON_TRUST_PROXY:1}"` under `ui.config.server` if you want it env-overridable. `server.trustProxy` is read once when the HTTP server is constructed, so it only takes effect on a pod restart — the Deployment's `checksum/config` annotation makes `helm upgrade` do that for you.

## Replicas and sticky sessions

The Horizon BFF holds its session table **in memory**, and the Deployment uses `strategy: Recreate` for that reason. `ui.replicas` defaults to `1`; raising it without sticky routing on your ingress breaks logins on requests that land on the other pod. Keep it at `1` unless your ingress controller is configured for session affinity.

## Related

- [Horizon UI in This Chart](../ui/horizon-ui.md)
- [Set Up Logins](../ui/logins.md)
- [TLS](tls.md)
- [UI and Login Problems](../troubleshooting/ui-and-login.md)
- [horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md)
