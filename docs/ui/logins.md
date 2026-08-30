# Set Up Logins

Horizon UI ships with **no accounts at all**, and a chart install that skips this page produces a
Deployment that reports healthy while nobody can sign in. This page shows how to confirm that state,
how to seed a throwaway demo login, and how to configure real users from a Kubernetes Secret.

## There is no default login, and the pod still goes Ready

Horizon has no built-in `admin/admin` fallback, and the chart configures no users of its own. The BFF
does **not** fail closed when it finds none: it boots, logs an error, serves the login page, and
answers its readiness probe with `200`. The result is a green deployment nobody can use.

| what you see | what is actually happening |
|---|---|
| Pod `1/1 Running`, Ready | `ui.readinessProbe` hits `/api/auth/health`, which is public and always answers `200` |
| Login page renders, with a setup banner | The page reads `configured: false` from that same endpoint |
| Every username/password is rejected | `auth.local.users` is empty, so no credential can match |

Confirm it from outside the pod — `configured` and `setupHint` are the two fields that matter:

```shell
kubectl port-forward -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  svc/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui 8080:80
curl -s http://127.0.0.1:8080/api/auth/health
```

```json
{"backend":"local","configured":false,"setupHint":"No users configured. Add at least one entry to auth.local.users in horizon.yaml ...","ldap":null,"breakGlass":{"armed":false}}
```

The same state appears once in the UI container log at startup:

```shell
kubectl logs -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui | grep 'auth.local.users is empty'
```

## Demo logins (publicly-known credentials)

For a first run on a trusted network, paste this into a values file. It seeds `admin/admin` and
`skywalking/skywalking` using `argon2id` hashes of those exact plaintexts — the same pair the chart's
own e2e tests use.

> **These hashes are published in this repository.** Anyone can read them and derive the passwords.
> Use them only on a network you control, and replace them before the UI is reachable by anyone else.

```yaml
# demo-values.yaml
ui:
  config:
    auth:
      backend: local          # the default; shown for clarity
      local:
        users:
          - username: admin            # password: admin
            passwordHash: "$argon2id$v=19$m=65536,t=3,p=4$eemqy1r72oSXR58y8VpRqw$Bn/dULrmJTHEi3263KfgWDEwQmUsqNLi3xwyv/DekHM"
            roles: [admin]
          - username: skywalking       # password: skywalking
            passwordHash: "$argon2id$v=19$m=65536,t=3,p=4$Zqj8HhQDqm8d5c2MipHYZw$BsaCnu4bdd4uadIldx3wwYLsdo47Thxb7Lv1MXpWG2Q"
            roles: [viewer, maintainer]
```

```shell
helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set ui.image.tag=horizon-1.0.0 \
  -f demo-values.yaml
```

Then port-forward and log in as `admin/admin`:

```shell
kubectl port-forward -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  svc/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui 8080:80
open http://127.0.0.1:8080
```

Pass the hashes through a values **file**, not `--set`: a hash is full of `,` and `=`, which `--set`
reads as its own separators (and of `$`, which the shell would expand first).

## Production: hashes from a Secret

Generate your own hash first. The CLI lives in the Horizon UI repository and reads the password from
`argv` or stdin:

```shell
git clone https://github.com/apache/skywalking-horizon-ui.git
cd skywalking-horizon-ui && pnpm install
HASH=$(pnpm --filter bff cli:hash 'your-strong-password' | tail -1)
```

Passwords longer than 64 characters are refused — the login route rejects them too, so a hash of one
could never be signed in with.

From there, pick one of two shapes. Both put the hash in a Secret and reference it with
`ui.envFromSecret`, which the chart turns into an `envFrom.secretRef` on the UI container.

### Why a token in `ui.config` is required either way

The chart mounts its ConfigMap **over** the image's `/app/horizon.yaml`, and that rendered file
contains only `oap.*` and `server.*` — no `auth:` block. Horizon expands `${VAR}` over the raw text of
whatever file is at that path, so a `HORIZON_*` variable is read only if a matching token is present
in the text. `auth.local.users` has a plain `[]` schema default and is **not** env-backed.

**Setting `HORIZON_AUTH_LOCAL_USERS` through `ui.envFromSecret` alone therefore does nothing** — the
token it would fill is not in the file the chart mounted. You must write the token into `ui.config`.

### Option A — one JSON array for all users

Best when users are managed as a unit and you would rather not restate them in the values file.

```shell
kubectl create secret generic horizon-users \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --from-literal=HORIZON_AUTH_LOCAL_USERS='[{"username":"admin","passwordHash":"'"$HASH"'","roles":["admin"]}]'
```

```yaml
# my-values.yaml
ui:
  envFromSecret: horizon-users
  config:
    auth:
      local:
        users: "${HORIZON_AUTH_LOCAL_USERS:[]}"
```

The JSON must be a **single line** — it is substituted into YAML text, where a newline would end the
value. If the Secret key is missing or empty the token falls back to `[]`, which is the silent
lockout again, so check `/api/auth/health` after rolling out.

### Option B — a `${VAR}` per hash

Best when the user list is stable and belongs in version control, with only the secrets held out.

```shell
kubectl create secret generic horizon-admin \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --from-literal=HORIZON_ADMIN_HASH="$HASH"
```

```yaml
# my-values.yaml
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

Use `ui.extraEnv` instead of `ui.envFromSecret` when you want to pick individual keys out of an
existing Secret:

```yaml
ui:
  extraEnv:
    - name: HORIZON_ADMIN_HASH
      valueFrom:
        secretKeyRef:
          name: horizon-admin
          key: passwordHash
```

### Install with it

```shell
helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0 \
  --set ui.image.tag=horizon-1.0.0 \
  -f my-values.yaml
```

A `helm upgrade` that changes `ui.config` rolls the UI pod on its own: the Deployment carries a
`checksum/config` annotation over the rendered ConfigMap. Changing only the **Secret** does not — env
vars are read once at container start, so restart the Deployment yourself:

```shell
kubectl rollout restart -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui
```

## Roles

`roles` on a user is a list of role names from `rbac.roles`. Horizon ships four:

| role | grants |
|---|---|
| `viewer` | Read the data: metrics, traces, logs, alarms, events, topology, profiling, browser errors, overviews, inspect |
| `maintainer` | Viewer, plus platform reads — cluster health, TTL, OAP configuration |
| `operator` | Maintainer, plus writes — dashboard and overview templates, DSL rules, live debugging, profiling tasks, source maps. Alarm rules stay read-only for every role |
| `admin` | `*` |

A user with an empty `roles` list can sign in and see nothing. Define your own names by setting
`ui.config.rbac.roles`; see the [horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md).

## Beyond local users

LDAP, SSO (OIDC/OAuth2), break-glass accounts and API tokens are all configured under `auth` in the
same `ui.config` block, and follow the same rule: write the field there, keep the secret in a Secret
and reference it with a `${VAR}` token.

`auth.tokensFile` — API tokens for callers with no browser (scripts, CI, MCP clients) — takes a
**path**, not a value, so it also needs `ui.extraVolumes` / `ui.extraVolumeMounts`. See
[Configure Horizon](configure.md).

- [Horizon UI in This Chart](horizon-ui.md) — what the BFF is and how it talks to OAP
- [UI and Login Problems](../troubleshooting/ui-and-login.md) — symptoms and fixes
- [Access control (upstream)](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/access-control/local-backend.md)
