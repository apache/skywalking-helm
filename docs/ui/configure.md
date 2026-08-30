# Configure Horizon

How the chart configures the Horizon UI container: what it writes into `horizon.yaml`, why almost everything else should be an environment variable instead, and the two settings — `templates.mode` and `/data` persistence — that most deployments need to touch.

## The image is configured by environment variable

The Horizon image ships `/app/horizon.yaml` in which **every field is a `${HORIZON_*:default}` token**. Horizon expands `${...}` over the raw *text* of that file before parsing it as YAML, so the container is meant to run with the shipped file and only the env vars you care about.

Precedence is: **env var → the file's `:default` → the built-in schema default.**

Two consequences fall out of that, and both are the reason this chart writes as little as it does:

- A field written as a **plain literal** in the config file makes its `HORIZON_*` env var **silently inert** — the token it would have replaced is no longer there to expand.
- A field the file **omits** falls back to a built-in default, and only a handful of those consult the environment.

So a config file full of literals does not merely restate defaults — it disables most of the image's configuration surface. **Prefer [`ui.extraEnv` and `ui.envFromSecret`](#prefer-env-vars) for everything the chart does not compute.**

## What the chart writes

`ui.enabled` creates a ConfigMap named `{release}-skywalking-helm-ui` (key `horizon.yaml`), mounted over `/app/horizon.yaml` as a read-only `subPath`. The chart writes **only the values the image cannot know**, and writes them as tokens so env still wins:

| `horizon.yaml` field | Source in `values.yaml` | Written when |
|---|---|---|
| `oap.queryUrl` | in-cluster OAP service + `oap.ports.rest` (`12800`) | always |
| `oap.adminUrl` | in-cluster OAP service + `oap.ports.admin` (`17128`) | always |
| `oap.zipkinUrl` | in-cluster OAP service + `oap.ports.zipkin-query` + `/zipkin` | only when `oap.ports.zipkin-query` is set |
| `server.publicUrl` | first entry of `ui.ingress.hosts`, `https` if `ui.ingress.tls` is non-empty else `http` | only when `ui.ingress.enabled` **and** `ui.ingress.hosts` are set |
| `server.port` | `ui.service.internalPort` (`8081`) | always |

With chart defaults, the rendered file is just:

```yaml
oap:
  adminUrl: ${HORIZON_OAP_ADMIN_URL:http://sw-skywalking-helm-oap:17128}
  queryUrl: ${HORIZON_OAP_QUERY_URL:http://sw-skywalking-helm-oap:12800}
server:
  port: 8081
```

Add a Zipkin query port and an ingress and two more lines appear:

```yaml
oap:
  adminUrl: ${HORIZON_OAP_ADMIN_URL:http://sw-skywalking-helm-oap:17128}
  queryUrl: ${HORIZON_OAP_QUERY_URL:http://sw-skywalking-helm-oap:12800}
  zipkinUrl: ${HORIZON_OAP_ZIPKIN_URL:http://sw-skywalking-helm-oap:9412/zipkin}
server:
  port: 8081
  publicUrl: ${HORIZON_PUBLIC_URL:http://skywalking.example.com}
```

Render it yourself before installing:

```shell
helm template sw chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  -s templates/ui-configmap.yaml
```

Notes on the table:

- `oap.zipkinUrl` is omitted rather than blanked when no Zipkin port is exposed: Horizon's schema requires a valid URL there, and an empty value fails at boot.
- `server.port` is the one **literal**, not a token — the container port comes from `ui.service.internalPort`, so the BFF has to bind that same port. `HORIZON_SERVER_PORT` is therefore inert; change `ui.service.internalPort` instead. The probes follow it automatically — both target the container's named `page` port, so nothing else needs changing.
- `server.host` is not written at all — the image's own `ENV` already sets it to `0.0.0.0`.
- Anything equal to Horizon's own default is deliberately left out, so upstream owns it.

## Two kinds of setting, and only one works from a bare env var

Horizon reads the environment in two different ways, and the difference decides how you set a field:

- **Fields whose built-in default reads the environment.** Roughly eighteen of them, including
  `templates.mode`, `server.host`, `server.port`, `server.publicUrl`, and the whole `ai`, `mcp`,
  `oauth` and `audit.enabled` set. Omit them from `ui.config` and the matching `HORIZON_*` variable
  is honoured on its own.
- **Everything else.** Their defaults are plain literals, so a `HORIZON_*` variable reaches them
  **only** through a `${...}` token written into the mounted file. Setting the variable alone does
  nothing at all — silently.

`session.cookieSecure`, `server.trustProxy`, `auth.local.users` and `oap.auth` are all in the second
group. For those, put the token in `ui.config` and supply the value from the environment:

```yaml
ui:
  envFromSecret: horizon-secrets     # supplies HORIZON_OAP_AUTH
  extraEnv:
    - name: HORIZON_SESSION_COOKIE_SECURE
      value: "true"
    - name: HORIZON_TRUST_PROXY
      value: "1"
  config:
    session:
      cookieSecure: ${HORIZON_SESSION_COOKIE_SECURE:false}
    server:
      trustProxy: ${HORIZON_TRUST_PROXY:false}
    oap:
      auth: ${HORIZON_OAP_AUTH:null}
```

That keeps secrets out of the ConfigMap — the token is what is rendered, the value arrives at
container start. It is the same pattern [Set Up Logins](logins.md) uses for `auth.local.users`.

For the first group no token is needed:

```yaml
ui:
  extraEnv:
    - name: HORIZON_TEMPLATES_MODE      # works with ui.config left empty
      value: readonly
```

The full field list is owned upstream: [horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md).

## When to use `ui.config` anyway

`ui.config` is deep-merged **over** the chart-computed values, so it can pin any field regardless of env — which is exactly what you want for a value that must not be overridable, and exactly what you do not want everywhere else. It is `{}` by default.

Two rules:

- **A literal you write here kills that field's `HORIZON_*` var.** Writing `templates.mode: readonly` into `ui.config` means `HORIZON_TEMPLATES_MODE` no longer does anything for this deployment. That is fine when pinning is the intent.
- **`${VAR}` tokens you write here still expand.** This is how secrets stay out of the ConfigMap — write the shape in `ui.config`, keep the secret in a Secret referenced by `ui.envFromSecret` / `ui.extraEnv`:

```yaml
ui:
  envFromSecret: horizon-admin
  config:
    auth:
      local:
        users:
          - username: admin
            passwordHash: "${HORIZON_ADMIN_HASH}"
            roles: [admin]
```

Overriding a chart-computed URL — for example to point Horizon at an OAP outside the release — works the same way, but the env var is the lighter option:

```yaml
ui:
  extraEnv:
    - name: HORIZON_OAP_QUERY_URL
      value: http://oap.observability.svc:12800
```

## `templates.mode`

`live` (Horizon's default) reads and writes dashboard templates through OAP 11's `/ui-management/templates*` admin REST API and persists them in OAP storage. In that mode OAP is the only source: if the template store cannot be read, layer pages are blocked rather than falling back to the bundled templates.

**Against OAP 10.x you must set `readonly`.** OAP 10 does not serve that REST surface, so `live` blocks every layer-driven page. `readonly` renders the templates bundled in the image and makes the configuration surface display-only; dashboards, traces, logs, topology, alarms and profiling all work.

```yaml
ui:
  extraEnv:
    - name: HORIZON_TEMPLATES_MODE
      value: readonly
```

or, pinned in the file:

```yaml
ui:
  config:
    templates:
      mode: readonly
```

Changing the mode requires a BFF restart, not just a config reload.

## Persistence (`/data`)

The image declares `/data` as its state volume and routes the BFF's OAP wire debug log there (`HORIZON_WIRE_LOG_FILE=/data/horizon-wire.jsonl`, written only when `debugLog.enabled`); anything else you point at a path under `/data` lands there too. The chart always mounts a volume at `/data` — an `emptyDir` by default, so **that state is gone whenever the pod is replaced** (upgrade, reschedule, delete). Turn on a PVC for anything you intend to keep:

```yaml
ui:
  persistence:
    enabled: true
    size: 1Gi
    # storageClass: standard
    # existingClaim: my-horizon-data
```

| Value | Default | Notes |
|---|---|---|
| `ui.persistence.enabled` | `false` | `false` → `emptyDir`; `true` → PVC mounted at `/data` |
| `ui.persistence.existingClaim` | unset | use a pre-created PVC; otherwise the chart creates `{release}-skywalking-helm-ui-data` |
| `ui.persistence.storageClass` | unset | `-` renders an empty `storageClassName` |
| `ui.persistence.accessModes` | `[ReadWriteOnce]` | matches `ui.replicas: 1` |
| `ui.persistence.size` | `1Gi` | |
| `ui.persistence.annotations` | `{}` | applied to the chart-managed PVC |

The image runs as the non-root `horizon` user, so any volume mounted into the container must be group-writable by it. `ui.securityContext.fsGroup` defaults to `101` for exactly this reason — keep it (or set an equivalent) when you override `ui.securityContext`, and apply the same thought to anything you add through `ui.extraVolumeMounts`.

Keep `ui.replicas: 1`. The BFF holds its session table in memory, the Deployment uses the `Recreate` strategy for that reason, and a `ReadWriteOnce` PVC cannot be mounted by pods on two different nodes anyway.

## Settings that take a path, not a value

Two Horizon 1.0.0 settings are configured by filesystem path, so they need `ui.extraVolumes` / `ui.extraVolumeMounts`:

- `auth.tokensFile` — API tokens for callers with no browser (scripts, CI, MCP clients). Mount a Secret.
- `sourceMaps.bootMountDir` — durable `.map` files for the Browser Errors tab. The image sets this to `/app/sourcemaps`; without a volume there, runtime uploads live in BFF memory only and are lost on pod restart.

```yaml
ui:
  extraVolumes:
    - name: horizon-tokens
      secret:
        secretName: horizon-tokens
  extraVolumeMounts:
    - name: horizon-tokens
      mountPath: /app/tokens
      readOnly: true
  config:
    auth:
      tokensFile: /app/tokens/tokens.json
```

## Applying a change

The UI Deployment carries a `checksum/config` annotation over the rendered ConfigMap, because a `subPath` ConfigMap mount does **not** update inside a running container. Any change to `ui.config` — or to a value that feeds a computed field — therefore rolls the pod on the next `helm upgrade`. Changing `ui.extraEnv` rolls it too, and env is read once at process start — but editing the *contents* of the Secret behind `ui.envFromSecret` changes no pod field, so nothing rolls: `kubectl rollout restart` the Deployment yourself.

Verify what actually landed in the container:

```shell
kubectl exec -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -- cat /app/horizon.yaml
```

## Next

- [Horizon UI in This Chart](horizon-ui.md) — what the image is, and why booster UI is gone
- [Set Up Logins](logins.md) — no login is configured by default
- [UI Service and Ingress](../expose/ui-service-and-ingress.md) — where `server.publicUrl` comes from
- [UI and Login Problems](../troubleshooting/ui-and-login.md)
- [skywalking Chart values](../reference/skywalking-chart-values.md) — every `ui.*` value
