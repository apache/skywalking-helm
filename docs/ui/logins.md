# Set Up Logins

Horizon UI ships with **no accounts at all**, and a chart install that skips this page produces a
Deployment that reports healthy while nobody can sign in. This page shows how to confirm that state,
how to seed a throwaway demo login, and how to configure real users from a Kubernetes Secret.

Both paths set one variable, `HORIZON_AUTH_LOCAL_USERS`, whose value is a **JSON array of users**.
The image's `/app/horizon.yaml` reads it (`users: ${HORIZON_AUTH_LOCAL_USERS:[]}`), and the chart
mounts nothing over that file by default — so an environment variable is all it takes.

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
`skywalking/skywalking` using `argon2id` hashes of those exact plaintexts — byte-for-byte what
`test/e2e/values.yaml` feeds the chart's own e2e.

> **These hashes are published in this repository.** Anyone can read them and derive the passwords.
> Use them only on a network you control, and replace them before the UI is reachable by anyone else.

```yaml
# demo-values.yaml
ui:
  extraEnv:
    - name: HORIZON_AUTH_LOCAL_USERS
      value: >-
        [{"username":"admin","passwordHash":"$argon2id$v=19$m=65536,t=3,p=4$eemqy1r72oSXR58y8VpRqw$Bn/dULrmJTHEi3263KfgWDEwQmUsqNLi3xwyv/DekHM","roles":["admin"]},
        {"username":"skywalking","passwordHash":"$argon2id$v=19$m=65536,t=3,p=4$Zqj8HhQDqm8d5c2MipHYZw$BsaCnu4bdd4uadIldx3wwYLsdo47Thxb7Lv1MXpWG2Q","roles":["viewer","maintainer"]}]
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

Two rules for the value, both about how it is carried rather than what it means:

- Pass it through a values **file**, not `--set`: a hash is full of `,` and `=`, which `--set` reads
  as its own separators (and of `$`, which the shell would expand first).
- The value must reach the container as **one line**. Horizon expands the variable into the text of
  `horizon.yaml` and then parses the file, so a newline inside the value lands mid-sequence at column
  0 and the parse fails — the BFF exits at boot and the pod crash-loops. To wrap it for readability
  use a folded block (`>-`) with every continuation line at the **same** indentation as the first, as
  above: YAML folds those into single spaces. Indenting a continuation line deeper, or using `|-`,
  keeps the newline and breaks the pod.

## Production: users from a Secret

Generate your own hash first. The CLI lives in the Horizon UI repository and reads the password from
`argv` or stdin:

```shell
git clone https://github.com/apache/skywalking-horizon-ui.git
cd skywalking-horizon-ui && pnpm install
HASH=$(pnpm --filter bff cli:hash 'your-strong-password' | tail -1)
```

Passwords longer than 64 characters are refused — the login route rejects them too, so a hash of one
could never be signed in with.

Put the same JSON in a Secret, under the key `HORIZON_AUTH_LOCAL_USERS`:

```shell
kubectl create secret generic horizon-users \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --from-literal=HORIZON_AUTH_LOCAL_USERS='[{"username":"admin","passwordHash":"'"$HASH"'","roles":["admin"]}]'
```

Point the chart at it. `ui.envFromSecret` becomes an `envFrom.secretRef` on the UI container, so
**every** key of that Secret arrives as an environment variable — one Secret can carry the users,
`HORIZON_OAP_AUTH`, and anything else sensitive:

```yaml
# my-values.yaml
ui:
  envFromSecret: horizon-users
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
  -f my-values.yaml
```

Use `ui.extraEnv` instead when the users live under a different key of a Secret you already have,
or when you want only that one key out of it:

```yaml
ui:
  extraEnv:
    - name: HORIZON_AUTH_LOCAL_USERS
      valueFrom:
        secretKeyRef:
          name: horizon-users
          key: users.json
```

Check `/api/auth/health` after the rollout: an empty or missing value falls back to `[]`, which is
the silent lockout again. `configured: true` is the confirmation.

### Rolling the pod after a change

Editing `ui.extraEnv` changes a pod field, so `helm upgrade` rolls the UI on its own. Editing the
**contents** of the Secret behind `ui.envFromSecret` changes no pod field and rolls nothing — and env
is read once at container start, so restart it yourself:

```shell
kubectl rollout restart -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui
```

### If you also set `ui.config`

`ui.config` is empty by default and nothing is mounted. Setting it replaces the image's
`/app/horizon.yaml` with a rendered one — but the chart keeps the
`${HORIZON_AUTH_LOCAL_USERS:[]}` token in it unless you write users of your own, so the Secret above
keeps working either way. Write `auth.local.users` in `ui.config` only if you want to pin users
regardless of the environment.

## Roles

`roles` on a user is a list of role names from `rbac.roles`. Horizon ships four:

| role | grants |
|---|---|
| `viewer` | Read the data: metrics, traces, logs, alarms, events, topology, profiling, browser errors, overviews, inspect |
| `maintainer` | Viewer, plus platform reads — cluster health, TTL, OAP configuration |
| `operator` | Maintainer, plus writes — dashboard and overview templates, DSL rules, live debugging, profiling tasks, source maps. Alarm rules stay read-only for every role |
| `admin` | `*` |

A user with an empty `roles` list can sign in and see nothing. Define your own names with
`HORIZON_RBAC_ROLES`, whose value is the whole `rbac.roles` block as JSON; see the
[horizon.yaml reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md).

## Beyond local users

The other auth backends work the same way — one variable, one JSON value, from `ui.extraEnv` or a
Secret via `ui.envFromSecret`:

| what | variable | value |
|---|---|---|
| Pick the backend | `HORIZON_AUTH_BACKEND` | `local` (default) or `ldap` |
| LDAP directory | `HORIZON_AUTH_LDAP` | `{"url":"ldaps://ldap.corp:636","userBaseDn":"...","groupMappings":[...]}` |
| SSO (OIDC/OAuth2) | `HORIZON_AUTH_SSO` | `{"providers":[...],"roles":{...}}`; additive to the backend, not a replacement |
| Break-glass account | `HORIZON_AUTH_BREAK_GLASS` | JSON; honoured only with `backend: ldap`, and only while the LDAP probe fails |

`auth.tokensFile` — API tokens for callers with no browser (scripts, CI, MCP clients) — is the
exception: `HORIZON_AUTH_TOKENS_FILE` takes a **path**, not a value, so the tokens themselves need
`ui.extraVolumes` / `ui.extraVolumeMounts`. See [Configure Horizon](configure.md).

- [Horizon UI in This Chart](horizon-ui.md) — what the BFF is and how it talks to OAP
- [UI and Login Problems](../troubleshooting/ui-and-login.md) — symptoms and fixes
- [Access control (upstream)](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/access-control/local-backend.md)
