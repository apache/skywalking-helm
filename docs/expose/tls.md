# TLS

How to serve the Horizon UI over HTTPS: create the certificate Secret, wire it into
`ui.ingress.tls`, and tell Horizon it is now behind TLS so session cookies are marked
`Secure`.

## What terminates TLS

The chart does not serve HTTPS itself. The Horizon BFF container listens on plain HTTP
(`ui.service.internalPort`, default `8081`) and the Service forwards
`ui.service.externalPort` (default `80`) to it. TLS terminates at your **ingress
controller**, using a Kubernetes TLS Secret that you reference from `ui.ingress.tls`.

A cloud load balancer can terminate it instead — `ui.service.type: LoadBalancer` plus a
cert annotation in `ui.service.annotations` (values.yaml shows the AWS ACM one). That path
skips the Ingress, so the chart derives no `server.publicUrl` for you and you set it in
`ui.config.server.publicUrl` yourself; the rest of this page still applies.

So "enable TLS" is two steps that must both happen:

1. Give the ingress a certificate (`ui.ingress.tls`).
2. Tell Horizon it is being reached over `https` (`ui.config.session.cookieSecure`, and
   usually `ui.config.server.trustProxy`).

Step 2 is not automatic. Skipping it still leaves a working UI — the session cookie is
`SameSite=strict`, so the browser keeps sending it over HTTPS — but the cookie carries no
`Secure` flag and would go out in clear on any plain-HTTP request to the same host. See
[Mark session cookies Secure](#mark-session-cookies-secure).

## Create the TLS Secret

The Secret must live in the release namespace and be of type `kubernetes.io/tls`.

```shell
kubectl create secret tls skywalking-tls \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key
```

If you run [cert-manager](https://cert-manager.io/docs/), do not create the Secret by
hand — name it in `ui.ingress.tls[].secretName` and let the issuer fill it in. The chart
renders `ui.ingress.annotations` onto the Ingress verbatim, so the usual annotations work:

```yaml
ui:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - skywalking.example.com
    tls:
      - secretName: skywalking-tls
        hosts:
          - skywalking.example.com
```

## Wire `ui.ingress.tls`

`ui.ingress.tls` is passed through to the Ingress `spec.tls` list unchanged, so it takes
the standard Kubernetes shape — a list of `{secretName, hosts}` entries. Default is `[]`.

```yaml
ui:
  ingress:
    enabled: true
    hosts:
      - skywalking.example.com
    tls:
      - secretName: skywalking-tls
        hosts:
          - skywalking.example.com
```

Rendering that gives:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-release-skywalking-helm-ui
spec:
  rules:
    - host: skywalking.example.com
      http:
        paths:
          - path: /
            backend:
              service:
                name: my-release-skywalking-helm-ui
                port:
                  number: 80
            pathType: Prefix
  tls:
    - hosts:
      - skywalking.example.com
      secretName: skywalking-tls
```

The hostnames in `ui.ingress.tls[].hosts` should match the entries in `ui.ingress.hosts`,
or the controller will not find a certificate for the request's `Host`.

## What setting `ui.ingress.tls` changes on its own

One thing, and it is in the ConfigMap rather than the Ingress:

| | |
|---|---|
| `server.publicUrl` | written only when `ui.ingress.enabled` **and** `ui.ingress.hosts` is non-empty; derived from the **first** `ui.ingress.hosts` entry, with scheme `https` when `ui.ingress.tls` is non-empty and `http` otherwise |

Horizon uses `publicUrl` to build SSO callbacks and as its OAuth issuer, so an `http://`
issuer on an HTTPS deployment breaks logins. Setting `ui.ingress.tls` flips it for you:

```yaml
    server:
      port: 8081
      publicUrl: ${HORIZON_PUBLIC_URL:https://skywalking.example.com}
```

Everything else about TLS you set yourself.

## Mark session cookies Secure

`session.cookieSecure` tells the BFF to set the `Secure` attribute on the session cookie.
Horizon's default is `false`, and the BFF logs a warning at boot when it is `false` outside
development.

Set it to `true` once you serve over HTTPS:

```yaml
ui:
  config:
    session:
      cookieSecure: true
```

**Set it in `ui.config`, not as an env var.** The `HORIZON_SESSION_COOKIE_SECURE`
environment variable is inert under this chart. The chart mounts its own generated
`horizon.yaml` over `/app/horizon.yaml`, and that file omits the `session:` block
entirely. Horizon expands `${...}` over the raw *text* of the config file, so with no
`session:` block there is no token to expand and the schema default (`false`) wins —
`ui.extraEnv` will not change it. This is the general rule for the chart's ConfigMap and
is covered in [Configure Horizon](../ui/configure.md).

If you still want the value overridable by env — for example to keep one values file for
both an HTTP dev cluster and an HTTPS production one — write the token yourself, quoted so
Helm keeps it a string:

```yaml
ui:
  config:
    session:
      cookieSecure: "${HORIZON_SESSION_COOKIE_SECURE:true}"
```

which renders into `horizon.yaml` as an expandable token that still defaults to `true`:

```yaml
    session:
      cookieSecure: ${HORIZON_SESSION_COOKIE_SECURE:true}
```

### Why it matters

Browsers refuse to store or send a `Secure` cookie over plain HTTP. The two failure modes
are symmetric:

| Setting | Served over | Result |
|---|---|---|
| `cookieSecure: true` | `http://` | Browser drops the cookie. Login "succeeds" and immediately bounces back to the login page. |
| `cookieSecure: false` | `https://` | Login works, but the session cookie has no `Secure` flag and would be sent in clear on any HTTP request to the same host. |

So flip `cookieSecure` in the same change that adds `ui.ingress.tls`, and flip it back if
you drop to plain HTTP. A `kubectl port-forward` to `http://localhost` is the usual
exception — most browsers treat localhost as a secure origin and keep the cookie — but if
a port-forward login bounces you straight back to the login page, `cookieSecure` is the
first thing to check.

## Record the real client address

Behind an ingress, every request appears to come from the ingress. To make the login audit
record the actual client, set `server.trustProxy`:

```yaml
ui:
  config:
    server:
      trustProxy: 1        # one proxy in front; or an address / CIDR
```

Use a hop count (`1` = a single proxy in front of the BFF) or the ingress address/CIDR.
`trustProxy: true` is **refused at boot** — it would trust the whole `X-Forwarded-For`
header, letting any caller choose the address that gets recorded. A `/0` block is refused
for the same reason, and a hostname is refused because the underlying server accepts only
addresses.

`server.trustProxy` is read once when the HTTP server is constructed, so it takes effect
only on pod restart.

## Full example

```yaml
# tls-values.yaml
ui:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - skywalking.example.com
    tls:
      - secretName: skywalking-tls
        hosts:
          - skywalking.example.com
  config:
    session:
      cookieSecure: true
    server:
      trustProxy: 1
```

```shell
helm upgrade --install "${SKYWALKING_RELEASE_NAME}" \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=horizon-1.0.0 \
  --set eck-operator.installCRDs=false \
  -f tls-values.yaml
```

`helm upgrade` does not carry `--set` values over from the previous release, so repeat
every flag the original install used — the storage ones included. The flags above match
the Elasticsearch install in [Quick Start](../install/quick-start.md); a BanyanDB or
PostgreSQL release has its own set (see [Pick a Storage Backend](../storage/choose-a-backend.md)).

Changing `ui.config` changes the UI ConfigMap, and the Deployment carries a
`checksum/config` annotation over it, so the UI pod is recreated on upgrade. Horizon's BFF
keeps its session table in memory, so everyone logged in is logged out by that restart.

## Verify

```shell
# The Ingress advertises the secret
kubectl get ingress -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -o jsonpath='{.items[*].spec.tls}'

# The Secret exists and is a TLS secret
kubectl get secret skywalking-tls -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -o jsonpath='{.type}'

# horizon.yaml has the https publicUrl and Secure cookies
kubectl get configmap "${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -o jsonpath='{.data.horizon\.yaml}'

# The certificate served on the wire
curl -vI https://skywalking.example.com 2>&1 | grep -i 'subject\|issuer'
```

## What this page does not cover

- **TLS on the OAP endpoints** (gRPC `11800`, REST `12800`) for agents. Those are plain
  Services, not an Ingress — see [OAP Endpoints for Agents](oap-endpoints.md).
- **TLS between OAP and storage.** Elasticsearch HTTP TLS is disabled by default in this
  chart (`elasticsearch.http.tls.selfSignedCertificate.disabled: true`) so OAP can connect
  without trusting the self-signed certificate — see
  [Elasticsearch](../storage/elasticsearch.md).

## Related

- [UI Service and Ingress](ui-service-and-ingress.md) — service types, hosts, paths
- [Configure Horizon](../ui/configure.md) — how `ui.config` and `HORIZON_*` env vars interact
- [Set Up Logins](../ui/logins.md) — local users, SSO, and the `publicUrl` an SSO callback needs
- [UI and Login Problems](../troubleshooting/ui-and-login.md)
- [`horizon.yaml` reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md)
