# UI and Login Problems

Symptom-keyed fixes for the Horizon UI deployed by this chart: a Ready pod nobody can sign into,
empty layer pages, `HORIZON_*` variables that do nothing, broken SSO redirects, sessions that drop,
and `swctl` calls that used to work against the UI. For install-time crashes and `CrashLoopBackOff`,
see [Install and Startup Failures](install-and-startup.md).

Two names are used throughout: the UI Service is `${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui`,
the OAP Service is `${SKYWALKING_RELEASE_NAME}-skywalking-helm-oap`.

| Symptom | Cause | Fix |
|---|---|---|
| Pod Ready, every login rejected | No users configured | [Seed `auth.local.users`](#the-pod-is-ready-but-nobody-can-log-in) |
| Layer pages blank, "template store unreachable" | OAP 10.x + `templates.mode: live` | [`templates.mode: readonly`](#layer-pages-are-empty-behind-a-dashboard-template-store-unreachable-banner) |
| A `HORIZON_*` env var is ignored | A literal in `ui.config` shadows it | [Write a `${...}` token instead](#a-horizon_-env-var-has-no-effect) |
| SSO callback hits the internal address | `server.publicUrl` unset or wrong | [Set `publicUrl`](#sso-callback-or-oauth-issuer-points-at-the-internal-address) |
| Logged out on every other request | `ui.replicas > 1`, no sticky routing | [Back to one replica](#logins-drop-on-every-other-request) |
| `swctl` against the UI fails | No `/graphql` passthrough | [Target OAP `12800`](#swctl-against-the-ui-returns-404-or-html) |

## The pod is Ready but nobody can log in

Horizon has no `admin/admin` fallback and the chart configures no users. The BFF **does not fail
closed**: with an empty user list it boots, logs an error, serves the login page, and answers its
readiness probe with `200`. Kubernetes therefore reports a perfectly healthy Deployment while every
credential is rejected.

`ui.readinessProbe` hits `/api/auth/health`, which is a public route by design — it is what the login
page reads to render its setup banner — so its `200` says nothing about whether auth works. The
response body does:

```shell
kubectl port-forward -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  svc/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui 8080:80
curl -s http://127.0.0.1:8080/api/auth/health
```

```json
{"backend":"local","configured":false,"setupHint":"No users configured. Add at least one entry to auth.local.users in horizon.yaml (use `pnpm --filter bff cli:hash` for the password hash) or switch to LDAP.","ldap":null,"breakGlass":{"armed":false}}
```

`configured: false` is the whole diagnosis. The same state appears once in the container log at boot:

```shell
kubectl logs -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui | grep 'auth.local.users is empty'
```

Fix it by seeding users — see [Set Up Logins](../ui/logins.md) for the demo snippet and the
production Secret pattern. Re-check `/api/auth/health` after the rollout; `configured: true` is the
confirmation.

Two things also produce `configured: false` with an LDAP backend: `auth.backend: ldap` with no
`auth.ldap` block, and an `auth.ldap` whose `groupMappings` list is empty. `setupHint` names which.

## Layer pages are empty behind a "Dashboard template store unreachable" banner

Full-width banner reading **Dashboard template store unreachable**, with "Layer dashboards, overviews
and topology are blocked until OAP's UI-template store is reachable." Traces, logs and alarms may
still render.

Horizon's default `templates.mode` is `live`, which reads dashboard definitions from OAP 11's
`/ui-management/templates*` admin REST API and treats the OAP-stored row as the only source — an
unreachable store blocks the page rather than quietly substituting the bundled defaults. Two things
trigger it:

- **You are running OAP 10.x.** OAP 10 has only a legacy GraphQL template API, which Horizon does
  not consume, and Horizon does not fall back on your behalf. Set `readonly`:

  ```shell
  --set ui.config.templates.mode=readonly
  ```

  In `readonly` mode Horizon renders the templates bundled in its own image and never calls a
  template-management API. Dashboards, traces, logs, topology, alarms and profiling all work; the
  template configuration surface becomes display-only.

- **You are on OAP 11 and the admin port is not reachable.** The chart points `oap.adminUrl` at
  `oap.ports.admin` (`17128`). If that port was removed from `oap.ports`, or a NetworkPolicy blocks
  it, `live` mode has nothing to read. Confirm from inside the UI pod:

  ```shell
  kubectl exec -n "${SKYWALKING_RELEASE_NAMESPACE}" \
    deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -- \
    wget -qO- http://${SKYWALKING_RELEASE_NAME}-skywalking-helm-oap:17128/ui-management/templates
  ```

  That is the exact path Horizon probes at boot. A connection refused or a 404 is the problem.

Note that `oap.ports.admin` is required for OAP 11 regardless of template mode — `/status/*` and
`/debugging/*` are served only there. See [Horizon UI in This Chart](../ui/horizon-ui.md).

## A `HORIZON_*` env var has no effect

You added a variable through `ui.extraEnv` or `ui.envFromSecret`, the pod restarted, and the setting
did not change.

The chart mounts its ConfigMap **over** the image's `/app/horizon.yaml`. Horizon expands `${...}`
over the raw **text** of whatever file sits at that path, before parsing it as YAML. So a
`HORIZON_*` variable is read in exactly two situations:

1. A matching `${HORIZON_*:default}` token appears in the mounted file's text, or
2. The field is absent from the file **and** its schema default itself reads `process.env` — true for
   only a handful of fields, `templates.mode` and `server.publicUrl` among them.

That is why the chart writes its computed values as tokens rather than literals:

```yaml
oap:
  adminUrl: ${HORIZON_OAP_ADMIN_URL:http://sw-skywalking-helm-oap:17128}
  queryUrl: ${HORIZON_OAP_QUERY_URL:http://sw-skywalking-helm-oap:12800}
server:
  port: 8081
```

The in-cluster address is the default and the env var still wins. Anything **you** write into
`ui.config`, when you set it, is emitted as a plain literal, and a literal makes the matching variable inert — which is
why `ui.config` is empty by default.

Check what actually got mounted before anything else:

```shell
kubectl get cm -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  ${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -o jsonpath='{.data.horizon\.yaml}'
```

| What the file shows | What the env var does |
|---|---|
| `queryUrl: ${HORIZON_OAP_QUERY_URL:...}` | Overrides it |
| `queryUrl: http://my-oap:12800` (your literal) | Ignored |
| Field absent, schema default reads env (e.g. `templates.mode`) | Overrides it |
| Field absent, schema default is a constant (e.g. `auth.local.users`) | Ignored |

The fix is to write the token yourself in `ui.config` rather than the value:

```yaml
ui:
  envFromSecret: horizon-secrets
  config:
    oap:
      queryUrl: "${HORIZON_OAP_QUERY_URL:http://sw-skywalking-helm-oap:12800}"
```

One more failure mode in the same family: changing only the **Secret** does not restart anything. The
Deployment carries a `checksum/config` annotation over the rendered ConfigMap, so `ui.config` edits
roll the pod, but env vars are read once at container start. After editing a Secret:

```shell
kubectl rollout restart -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  deploy/${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui
```

Details and the full field table are in [Configure Horizon](../ui/configure.md).

## SSO callback or OAuth issuer points at the internal address

The provider rejects the redirect URI, or the browser is bounced to something like
`http://sw-skywalking-helm-ui:8081/api/auth/oidc/callback` after signing in.

Horizon builds the OIDC callback URI from `server.publicUrl`; when that is blank it falls back to the
request's own origin (`req.protocol` + the `Host` header). Behind an ingress that rewrites `Host`, or
anywhere TLS terminates upstream, that fallback produces the internal address. `oauth.issuer` also
defaults to `server.publicUrl`, so the same blank value gives you a wrong issuer.

The chart derives `publicUrl` automatically, but **only when both** `ui.ingress.enabled` is true
**and** `ui.ingress.hosts` is non-empty — it takes the first host, with `https` when
`ui.ingress.tls` is set and `http` otherwise:

```yaml
server:
  port: 8081
  publicUrl: ${HORIZON_PUBLIC_URL:http://skywalking.example.com}
```

So it is absent when you expose the UI by LoadBalancer, NodePort, or a Gateway API / service-mesh
route instead of the chart's Ingress. Set it yourself in that case, either as env:

```yaml
ui:
  extraEnv:
    - name: HORIZON_PUBLIC_URL
      value: https://skywalking.example.com
```

or pinned in `ui.config.server.publicUrl`. Two rules: it must be **byte-identical** to the redirect
URI registered with the provider, and if a gateway serves Horizon under a path prefix
(`https://example.com/horizon/`), `publicUrl` must carry that prefix — it is also what the BFF uses
to build root-relative redirects back to `/login`.

While you are here, two neighbouring settings, both plain environment variables:

```yaml
ui:
  extraEnv:
    - name: HORIZON_SESSION_COOKIE_SECURE
      value: "true"        # serving over HTTPS
    - name: HORIZON_TRUST_PROXY
      value: "1"           # hop count — 1 = one proxy in front; an address/CIDR list also works
```

`trustProxy` is what makes the login audit record the real client address rather than the ingress.
`trustProxy: true` is refused at boot. See [TLS](../expose/tls.md) and
[UI Service and Ingress](../expose/ui-service-and-ingress.md).

## Logins drop on every other request

You sign in, click once, and land back on the login page — then it works again, then it does not.

The Horizon BFF keeps its session table **in memory**, per pod. Two pods hold disjoint session state,
so requests round-robined between them are authenticated only half the time. This is why
`ui.replicas` defaults to `1` and why the UI Deployment uses `strategy: Recreate` rather than
`RollingUpdate` — a rolling update would open the same window during every upgrade.

```shell
kubectl get deploy -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  ${SKYWALKING_RELEASE_NAME}-skywalking-helm-ui -o jsonpath='{.spec.replicas}'
```

If that is greater than `1`, either go back to one replica:

```shell
--set ui.replicas=1
```

or configure session affinity on your ingress controller. The chart exposes no `sessionAffinity`
field on the UI Service, so this has to come from `ui.ingress.annotations` — for ingress-nginx:

```yaml
ui:
  replicas: 2
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/affinity: "cookie"
      nginx.ingress.kubernetes.io/session-cookie-name: "horizon-route"
    hosts:
      - skywalking.example.com
```

Two related non-bugs: a `helm upgrade` that changes `ui.config` rolls the pod and drops every session
by design, and `ui.persistence` with the default `ReadWriteOnce` access mode cannot be shared by two
pods at all.

## `swctl` against the UI returns 404 or HTML

A command that used to work — `swctl --base-url=http://<ui>/graphql ...` — now fails.

Horizon's BFF **does not proxy `/graphql`** to OAP. It talks to OAP itself on the query port
(`12800`) and the admin port (`17128`) and exposes its own `/api/*` surface; there is no passthrough
for external GraphQL clients, and the UI container listens on `8081` rather than the `8080` the
legacy booster UI used. Point every API caller at the OAP Service directly:

```shell
kubectl port-forward -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  svc/${SKYWALKING_RELEASE_NAME}-skywalking-helm-oap 12800:12800

swctl --display yaml --base-url=http://127.0.0.1:12800/graphql service ls
```

In-cluster, that is
`http://${SKYWALKING_RELEASE_NAME}-skywalking-helm-oap:12800/graphql`. The chart's own e2e suites do
the OAP Service directly on `12800`.

For a caller that genuinely needs Horizon's own API rather than OAP's — a script, CI job, or MCP
client — use Horizon API tokens instead. `auth.tokensFile` takes a filesystem **path**, so it needs a
mounted Secret via `ui.extraVolumes` / `ui.extraVolumeMounts`; see
[Configure Horizon](../ui/configure.md).

## Related pages

- [Set Up Logins](../ui/logins.md) — seeding users, hashes, roles
- [Configure Horizon](../ui/configure.md) — the full `ui.config` / env surface
- [Horizon UI in This Chart](../ui/horizon-ui.md) — ports, versions, migration from booster UI
- [UI Service and Ingress](../expose/ui-service-and-ingress.md) — exposing the UI
- [`horizon.yaml` reference](https://github.com/apache/skywalking-horizon-ui/blob/main/docs/setup/horizon-yaml.md) — the upstream schema
