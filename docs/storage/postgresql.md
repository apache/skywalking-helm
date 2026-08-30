# PostgreSQL

How to run OAP on PostgreSQL with this chart — either the bundled demo database (`postgresql.enabled=true`) or a PostgreSQL server you already operate — and exactly which connection environment variables the chart derives for the OAP pods.

## The bundled PostgreSQL is a demo, not a production database

`chart/skywalking/values.yaml` says so in the value itself:

```yaml
postgresql:
  enabled: false # Whether to start a demo postgresql deployment, don't use this for production.
```

What that means concretely:

| What the chart does | Consequence |
| --- | --- |
| Ships `primary.persistence.enabled: false` and `readReplicas.persistence.enabled: false` | The Bitnami StatefulSet gets no `volumeClaimTemplates` — its `data` volume is `emptyDir: {}` and is not even mounted, so PGDATA lives in the pod's writable layer and every trace and metric is gone when the pod restarts. |
| Ships literal credentials (`auth.password: "123456"`) | They are rendered as plain `env` values in the OAP pod spec, not a `secretKeyRef` (see below). |
| Pins the Bitnami `postgresql` subchart to 12.1.2 from the `archive-full-index` repo (`chart/skywalking/Chart.yaml`) | The image is `docker.io/bitnami/postgresql:15.1.0-debian-11-r0`; the chart and image are frozen, so a chart bump brings you no PostgreSQL patches. |
| Runs no PostgreSQL e2e job — `.github/workflows/e2e.ci.yaml` covers Elasticsearch and BanyanDB only | This path is not exercised on every commit. |

For anything real, either set `postgresql.enabled: false` and point at a PostgreSQL you (or your cloud provider) run, or pick [BanyanDB](banyandb.md) / [Elasticsearch](elasticsearch.md) — see [Pick a Storage Backend](choose-a-backend.md).

## Values

| Value | Default | Effect |
| --- | --- | --- |
| `postgresql.enabled` | `false` | Deploy the bundled Bitnami PostgreSQL subchart (`condition: postgresql.enabled`). |
| `postgresql.config.host` | `postgresql-service.your-awesome-company.com` | Hostname of your own PostgreSQL. Used **only** when `postgresql.enabled: false`. |
| `postgresql.auth.postgresPassword` | `"123456"` | Password of the `postgres` superuser in the bundled database. |
| `postgresql.auth.username` | `postgres` | Goes into `SW_DATA_SOURCE_USER` and into the `pg_isready -U` probe. |
| `postgresql.auth.password` | `"123456"` | Goes into `SW_DATA_SOURCE_PASSWORD`. |
| `postgresql.auth.database` | `skywalking` | Database name in `SW_JDBC_URL`. |
| `postgresql.containerPorts.postgresql` | `5432` | Port in `SW_JDBC_URL` and in the wait probe — in **both** embedded and external mode. Both point at a Service, so in embedded mode change `postgresql.primary.service.ports.postgresql` (Bitnami's Service port, also `5432`) to match, or the URL points at a port nothing serves. |
| `postgresql.primary.persistence.enabled` | `false` | Bundled primary uses `emptyDir`. |
| `postgresql.readReplicas.persistence.enabled` | `false` | Same for read replicas (the subchart's default `architecture` is `standalone`, so none are deployed unless you change it). |

Any other key under `postgresql.` is passed straight through to the Bitnami subchart.

## Install with the bundled demo database

```shell
helm install skywalking \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n default \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=postgresql \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set postgresql.enabled=true
```

`elasticsearch.enabled=false` matters: the ES subchart and the ECK operator are enabled by default, so leaving it out deploys an Elasticsearch nobody reads from.

The chart addresses the bundled database as `<release-name>-postgresql` on `postgresql.containerPorts.postgresql`, which is the Service the Bitnami subchart creates for a release named `skywalking`.

## Point at your own PostgreSQL

Leave `postgresql.enabled` at `false` (the default) and set the host — the rest of the `auth` block still supplies the user, password, database and port:

```yaml
# my-postgres.yaml
oap:
  storageType: postgresql
elasticsearch:
  enabled: false
postgresql:
  enabled: false
  config:
    host: pg.example.com
  auth:
    username: skywalking
    password: "change-me"
    database: skywalking
  containerPorts:
    postgresql: 5432
```

```shell
helm install skywalking \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 \
  -n default \
  --set oap.image.tag=11.0.0 \
  --set ui.image.tag=horizon-1.0.0 \
  -f my-postgres.yaml
```

The database itself must exist before install; the chart only creates the SkyWalking schema inside it (via the [OAP init Job](../operate/oap-init-job.md)).

## What the chart derives

`skywalking.oap.envs.storage` in `templates/_helpers.tpl` builds these for **both** the OAP Deployment and the OAP init Job — rendered from the `my-postgres.yaml` above:

```yaml
- name: SW_STORAGE
  value: postgresql
- name: SW_JDBC_URL
  value: "jdbc:postgresql://pg.example.com:5432/skywalking"
- name: SW_DATA_SOURCE_USER
  value: "skywalking"
- name: SW_DATA_SOURCE_PASSWORD
  value: "change-me"
```

| Env var | Built from |
| --- | --- |
| `SW_STORAGE` | `oap.storageType` |
| `SW_JDBC_URL` | `jdbc:postgresql://<host>:<postgresql.containerPorts.postgresql>/<postgresql.auth.database>`, where `<host>` is `<release-name>-postgresql` when `postgresql.enabled: true`, otherwise `postgresql.config.host` |
| `SW_DATA_SOURCE_USER` | `postgresql.auth.username` |
| `SW_DATA_SOURCE_PASSWORD` | `postgresql.auth.password` |

These are the same knobs as the upstream `storage.postgresql` block: https://skywalking.apache.org/docs/main/latest/en/setup/backend/storages/postgresql/ — anything else on that page (HikariCP pool sizing, `SW_STORAGE_MAX_SIZE_OF_BATCH_SQL`, …) is not templated, so set it through `oap.env`:

```yaml
oap:
  env:
    SW_STORAGE_MAX_SIZE_OF_BATCH_SQL: "2000"
```

Both the Deployment and the init Job also get a `wait-for-postgresql` init container (image `postgres:13`, not overridable by `initContainer.image`) that loops on `pg_isready -h <host> -p <port> -U <postgresql.auth.username>` every 3 seconds:

```shell
until pg_isready -h 'skywalking-postgresql' -p '5432' -U 'postgres'; do
  echo "Waiting for postgresql..."
  sleep 3
done
```

Verify the whole thing without installing anything:

```shell
helm template skywalking chart/skywalking \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=postgresql \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set postgresql.enabled=true | grep -A1 'SW_JDBC_URL'
```

## Gotchas

**`auth.password` is ignored by the bundled database when the user is `postgres`.** With the default `auth.username: postgres`, the Bitnami StatefulSet takes `POSTGRES_PASSWORD` from the Secret key `postgres-password` (i.e. `auth.postgresPassword`) and never uses the `password` key it also writes, while OAP is handed `auth.password` as `SW_DATA_SOURCE_PASSWORD`. The defaults are both `"123456"` so it works out of the box, but changing only one of them gives OAP a password the database never had. Change both, or set a non-`postgres` `auth.username` — then Bitnami creates that user with `auth.password` and the two agree.

**Do not name the release `*postgresql*` with the bundled database.** The chart computes the host as `<release-name>-postgresql`, but Bitnami collapses its own name when the release already contains the chart name. Release `my-postgresql` yields the Service `my-postgresql` and `SW_JDBC_URL` of `jdbc:postgresql://my-postgresql-postgresql:5432/skywalking`, which never connects. The same mismatch appears if you set `postgresql.fullnameOverride` / `postgresql.nameOverride`. Workaround: run the database separately and use `postgresql.config.host`.

**The wait loop is unbounded.** Unlike the Elasticsearch and BanyanDB init containers, which give up after 60 attempts, `wait-for-postgresql` retries forever. An OAP pod stuck in `Init:0/1` with `Waiting for postgresql...` in the init container log means a wrong host, port, user, or a firewalled database — it will not fail on its own. See [Install and Startup Failures](../troubleshooting/install-and-startup.md).

**Credentials are visible in the pod spec.** `SW_DATA_SOURCE_PASSWORD` is a literal `value:`, and `oap.env` renders string values only (no `valueFrom`), so there is no supported way to source it from a Secret today. Anyone who can read the OAP Pod, Deployment or Job can read the password.
