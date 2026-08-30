# Configure Horizon

Horizon's image ships a complete `/app/horizon.yaml` in which **all 62 fields are
`${HORIZON_*:default}` placeholders**, expanded over the raw text of that file before it is parsed
as YAML. The chart mounts nothing over it. It sets the handful of values it can compute as plain
environment variables and leaves the image's file intact, so every other field stays settable from
the environment.

Precedence is: **env var → the file's `:default` → the built-in schema default.**

## Three mechanisms

| | Value | Reach for it when |
|---|---|---|
| 1. Environment variables | `ui.extraEnv` | Anything not sensitive. A list, so an entry may carry `valueFrom` |
| 2. A Secret's keys as environment variables | `ui.envFromSecret` | Password hashes, LDAP bind passwords, OAP credentials, API keys |
| 3. A `horizon.yaml` through a ConfigMap | `ui.config` | Pinning a field so no environment can change it — opt-in, and it **replaces** the image's file |

**Prefer 1 and 2.** They are how the image is meant to be configured, and they leave all 62 fields
reachable. `ui.config` is `{}` by default: no ConfigMap is created and nothing is mounted until you
set it.

Two rules govern how the two environment mechanisms combine, and both are plain Kubernetes:

- **`env` beats `envFrom`.** The chart's computed values are `env` entries, so a key of the same
  name in the Secret behind `ui.envFromSecret` is ignored. Override a chart-computed value with
  `ui.extraEnv` instead.
- **`ui.extraEnv` is appended after the computed entries**, and for a duplicate name the last entry
  is the one the container sees. That is what makes such an override work.

The field list itself is owned upstream:
[horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md).

## What the chart sets

| Environment variable | Value | Set when |
|---|---|---|
| `HORIZON_SERVER_PORT` | `ui.service.internalPort` (`8081`) | always |
| `HORIZON_OAP_QUERY_URL` | in-cluster OAP service + `oap.ports.rest` (`12800`) | always |
| `HORIZON_OAP_ADMIN_URL` | in-cluster OAP service + `oap.ports.admin` (`17128`) | only when `oap.ports.admin` is set |
| `HORIZON_OAP_ZIPKIN_URL` | in-cluster OAP service + `oap.ports.zipkin-query` + `/zipkin` | only when `oap.ports.zipkin-query` is set |
| `HORIZON_PUBLIC_URL` | first entry of `ui.ingress.hosts`, `https` when a `tls` block covers that host, else `http` | only when `ui.ingress.enabled` **and** `ui.ingress.hosts` are set |

With chart defaults that is three variables. Render it yourself before installing:

```shell
helm template sw chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  -s templates/ui-deployment.yaml
```

```yaml
        env:
        - name: HORIZON_SERVER_PORT
          value: "8081"
        - name: HORIZON_OAP_QUERY_URL
          value: "http://sw-skywalking-helm-oap:12800"
        - name: HORIZON_OAP_ADMIN_URL
          value: "http://sw-skywalking-helm-oap:17128"
```

Expose the Zipkin query port and a TLS ingress and the other two appear:

```yaml
        - name: HORIZON_OAP_ZIPKIN_URL
          value: "http://sw-skywalking-helm-oap:9412/zipkin"
        - name: HORIZON_PUBLIC_URL
          value: "https://skywalking.example.com"
```

Notes on the table:

- `HORIZON_OAP_ZIPKIN_URL` is omitted rather than blanked when no Zipkin port is exposed: Horizon's
  schema requires a valid URL there, and an empty value fails at boot. `HORIZON_OAP_ADMIN_URL` is
  conditional for a different reason — on OAP 10.x, port `17128` is the AI-pipeline URI-recognition
  server, not the admin REST host, so set `oap.ports.admin: null` there and the variable disappears.
- `HORIZON_PUBLIC_URL`'s scheme is derived **per host**, because a `tls` block may cover only some
  of them. A `tls` entry with no `hosts` is the controller's default certificate and covers this one.
  An entry in `ui.ingress.hosts` may carry a path (`skywalking.example.com/ui`); the whole entry
  becomes the public URL, while only the hostname before the first `/` is matched against
  `tls[].hosts`. SSO callbacks are built from that URL, so the path has to be the one the ingress
  actually serves the UI on.
- **`server.port` follows `ui.service.internalPort`.** The container port comes from the same value,
  and both probes target the container's named `page` port, so they follow it too. Do not override
  `HORIZON_SERVER_PORT` through `ui.extraEnv` — the BFF would bind a port nothing routes to. Change
  `ui.service.internalPort`.
- `server.host` is not set by the chart; the image's own `ENV` already carries
  `HORIZON_SERVER_HOST=0.0.0.0`.

## Environment variables (`ui.extraEnv`)

One variable per field, appended to the container's `env`:

```yaml
ui:
  extraEnv:
    - name: HORIZON_TEMPLATES_MODE
      value: readonly
    - name: HORIZON_SESSION_COOKIE_SECURE
      value: "true"
    - name: HORIZON_TRUST_PROXY
      value: "1"
    - name: HORIZON_OAP_QUERY_URL              # overrides the chart's computed value
      value: http://oap.observability.svc:12800
```

It is a list, so an entry may take its value from a single Secret key or the downward API rather
than from the values file:

```yaml
ui:
  extraEnv:
    - name: HORIZON_OAP_AUTH
      valueFrom:
        secretKeyRef:
          name: horizon-oap
          key: auth.json
```

### Structured blocks take JSON in one variable

Fields that are objects or lists rather than scalars take their **whole block** as JSON in a single
variable. A `:null` default in the shipped file means "fall through to the built-in default".

| Variable | Field |
|---|---|
| `HORIZON_AUTH_LOCAL_USERS` | `auth.local.users` |
| `HORIZON_AUTH_LDAP` | `auth.ldap` |
| `HORIZON_AUTH_BREAK_GLASS` | `auth.breakGlass` — honored only when `backend=ldap` and the LDAP probe is failing |
| `HORIZON_AUTH_SSO` | `auth.sso` |
| `HORIZON_RBAC_ROLES` | `rbac.roles` |
| `HORIZON_RBAC_LANDING_BY_ROLE` | `rbac.landingByRole` — post-login landing route per role |
| `HORIZON_OAP_AUTH` | `oap.auth` — basic-auth for the BFF's outbound calls to OAP |
| `HORIZON_OAP_MQE` | `oap.mqe` — host/port override, defaults to the query host |
| `HORIZON_PERFORMANCE` | `performance` — BFF→OAP fan-out and caps |
| `HORIZON_LAYERS_EXCLUDED` | `layers.excluded` — an array of `{key, reason}`; `[]` surfaces every reported layer |
| `HORIZON_AUDIT_POSTGRES` | `audit.postgres` — connection settings for the sign-in audit; a secret, so keep it in `ui.envFromSecret` |
| `HORIZON_AI_STARTERS` | `ai.starters` |
| `HORIZON_OAUTH_CLIENT_METADATA_HOSTS` | `oauth.clientMetadataHosts` |

Each variable carries the **whole** block, replacing it rather than merging into it — so restate the
parts of the default you want to keep. `layers.excluded` defaults to `FAAS` and `VIRTUAL_GATEWAY`,
which is why hiding one more means naming all three:

```yaml
ui:
  extraEnv:
    - name: HORIZON_LAYERS_EXCLUDED
      value: '[{"key":"FAAS"},{"key":"VIRTUAL_GATEWAY"},{"key":"SO11Y_OAP","reason":"Internal."}]'
    - name: HORIZON_PERFORMANCE
      value: '{"bulk":{"dashboard":{"bulkSize":8}}}'
```

The value is injected into the file's text and parsed there, so it must be a **single flow value** —
one line, or continuation lines indented under the first. A newline at column zero ends the value
and breaks the parse.

## Secrets (`ui.envFromSecret`)

`ui.envFromSecret` names a pre-created Secret and becomes an `envFrom.secretRef` on the UI
container, so **every** key of it arrives as an environment variable. One Secret carries everything
sensitive (`$HASH` below is an Argon2id password hash — [Set Up Logins](logins.md) mints one):

```shell
kubectl create secret generic horizon-secrets \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --from-literal=HORIZON_AUTH_LOCAL_USERS='[{"username":"admin","passwordHash":"'"$HASH"'","roles":["admin"]}]' \
  --from-literal=HORIZON_OAP_AUTH='{"username":"skywalking","password":"changeme"}'
```

```yaml
ui:
  envFromSecret: horizon-secrets
```

That is the whole configuration. Nothing has to be written into `ui.config` for those variables to
be read — the tokens they fill are already in the image's file.

## `ui.config`, and what it costs

Setting `ui.config` creates a ConfigMap named `{release}-skywalking-helm-ui` (key `horizon.yaml`)
and mounts it read-only as a `subPath` over `/app/horizon.yaml`. That **replaces** the image's file
rather than merging with it, which has two consequences:

- A field you do not write there falls back to Horizon's **built-in** default — not to the
  `:default` in the image's file, which is no longer present.
- That field's `HORIZON_*` variable stops working, because the token it would have expanded is gone.
  Silently.

The chart merges its computed values back in, so OAP stays reachable either way. The OAP URLs and
`server.publicUrl` go in as `${VAR:default}` tokens and stay env-overridable. `server.port` does
not — it is written as a literal, because the container port and both probes come from
`ui.service.internalPort` and the BFF has to bind the same one, so `HORIZON_SERVER_PORT` is the one
computed value `ui.config` really does make inert:

```shell
helm template sw chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set ui.config.templates.mode=readonly \
  -s templates/ui-configmap.yaml
```

```yaml
data:
  horizon.yaml: |
    oap:
      adminUrl: ${HORIZON_OAP_ADMIN_URL:http://sw-skywalking-helm-oap:17128}
      queryUrl: ${HORIZON_OAP_QUERY_URL:http://sw-skywalking-helm-oap:12800}
    server:
      port: 8081
    templates:
      mode: readonly
```

`templates.mode` is now pinned: `HORIZON_TEMPLATES_MODE` does nothing for this deployment, which is
exactly the point of writing it there. The same goes for any other field you put in `ui.config`.

Fields you leave out fall back to Horizon's built-in defaults, and their `HORIZON_*` variables have
no token to fill — with one exception the chart handles for you. `auth.local.users` keeps its
`${HORIZON_AUTH_LOCAL_USERS:[]}` token unless you write users yourself, so a deployment taking its
users from a Secret does not lose them the moment `ui.config` is set. The OAP URLs are preserved the
same way.

```yaml
ui:
  envFromSecret: horizon-secrets
  config:
    templates:
      mode: readonly
    auth:
      local:
        users: ${HORIZON_AUTH_LOCAL_USERS:[]}
```

Every field you want to stay env-settable needs its token restated like that, which is the whole
reason to prefer mechanisms 1 and 2 and to keep `ui.config` down to what must be pinned.

## Horizon is not OAP

Both components offer the same three mechanisms, but the balance between them is different, because
the two images read configuration differently:

| | Horizon (`ui.*`) | OAP (`oap.*`) |
|---|---|---|
| Environment variables | `ui.extraEnv` (list) | `oap.env` (map, no `valueFrom`) and `oap.extraEnv` (list) |
| From a Secret | `ui.envFromSecret` | `oap.envFromSecret` — applied to the OAP Deployment **and** the init Job |
| Files | `ui.config` — a last resort | `oap.config` — the only way to supply some things |

Horizon's entire configuration is one env-tokenized file the image already ships, so a file mount
buys nothing but the ability to pin. **OAP reads real files**: `log4j2.xml`, the OAL and MAL rule
sets, `metadata-service-mapping.yaml`. Its `application.yml` resolves settings as `${SW_*:default}`
the same way, so environment variables cover settings — but nothing except a mounted file can supply
a rule set, so `oap.config` stays a first-class mechanism there.

Use `oap.extraEnv` where `oap.env` cannot reach: it is a list, so entries may carry `valueFrom` for
a single credential out of a Secret or a value from the downward API. `oap.envFromSecret` covers the
init Job as well, which needs the same storage credentials as the Deployment. See
[Configure OAP](../operate/oap-configuration.md).

## `templates.mode`

`live` (Horizon's default) reads and writes dashboard templates through OAP 11's
`/ui-management/templates*` admin REST API and persists them in OAP storage. In that mode OAP is the
only source: if the template store cannot be read, layer pages are blocked rather than falling back
to the bundled templates.

**Against OAP 10.x you must set `readonly`.** OAP 10 does not serve that REST surface, so `live`
blocks every layer-driven page. `readonly` renders the templates bundled in the image and makes the
configuration surface display-only; dashboards, traces, logs, topology, alarms and profiling all
work.

```yaml
ui:
  extraEnv:
    - name: HORIZON_TEMPLATES_MODE
      value: readonly
```

Changing the mode requires a BFF restart, not just a config reload.

## Persistence (`/data`)

The image declares `/data` as its state volume and routes the BFF's OAP wire debug log there
(`HORIZON_WIRE_LOG_FILE=/data/horizon-wire.jsonl`, written only when `debugLog.enabled`); anything
else you point at a path under `/data` lands there too. The chart always mounts a volume at `/data`
— an `emptyDir` by default, so **that state is gone whenever the pod is replaced** (upgrade,
reschedule, delete). Turn on a PVC for anything you intend to keep:

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

The image runs as the non-root `horizon` user, so any volume mounted into the container must be
group-writable by it. `ui.securityContext.fsGroup` defaults to `101` for exactly this reason — keep
it (or set an equivalent) when you override `ui.securityContext`, and apply the same thought to
anything you add through `ui.extraVolumeMounts`.

Keep `ui.replicas: 1`. The BFF holds its session table in memory, the Deployment uses the `Recreate`
strategy for that reason, and a `ReadWriteOnce` PVC cannot be mounted by pods on two different nodes
anyway.

## Settings that take a path, not a value

Two Horizon 1.0.0 settings name a file or directory rather than carrying a value, so they need
`ui.extraVolumes` / `ui.extraVolumeMounts` — but the path itself is still an ordinary variable:

- `auth.tokensFile` (`HORIZON_AUTH_TOKENS_FILE`) — API tokens for callers with no browser (scripts,
  CI, MCP clients). Empty by default; mount a Secret and point the variable at it.
- `sourceMaps.bootMountDir` (`HORIZON_SOURCEMAPS_DIR`) — durable `.map` files for the Browser Errors
  tab. The image already sets it to `/app/sourcemaps`, so only the volume is missing; without one,
  runtime uploads live in BFF memory and are lost on pod restart.

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
  extraEnv:
    - name: HORIZON_AUTH_TOKENS_FILE
      value: /app/tokens/tokens.json
```

## Applying a change

| What you changed | Does the pod roll? |
|---|---|
| `ui.extraEnv`, or a value feeding a computed variable | Yes — the pod spec changed, so `helm upgrade` rolls it |
| The **contents** of the Secret behind `ui.envFromSecret` | No — no pod field changed |
| `ui.config` | Yes — the Deployment carries a `checksum/config` annotation over the rendered ConfigMap |

Environment is read once at process start, so a Secret edit needs a restart you ask for yourself:

```shell
kubectl rollout restart -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui
```

The `checksum/config` annotation exists only while `ui.config` is set, and it is there because a
`subPath` ConfigMap mount never updates inside a running container.

Verify what actually reached the container:

```shell
# what the chart and your values set
kubectl exec -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -- env | grep '^HORIZON_' | sort

# the file being expanded: the image's 62 tokens, unless ui.config is set
kubectl exec -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -- cat /app/horizon.yaml
```

For whether authentication took, `/api/auth/health` reports it without a login — see
[Set Up Logins](logins.md).

## Next

- [Horizon UI in This Chart](horizon-ui.md) — what the image is, and why booster UI is gone
- [Set Up Logins](logins.md) — no login is configured by default
- [Configure OAP](../operate/oap-configuration.md) — the same three mechanisms on the backend
- [UI Service and Ingress](../expose/ui-service-and-ingress.md) — where `HORIZON_PUBLIC_URL` comes from
- [UI and Login Problems](../troubleshooting/ui-and-login.md)
- [skywalking Chart values](../reference/skywalking-chart-values.md) — every `ui.*` value
