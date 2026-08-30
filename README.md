Apache SkyWalking Kubernetes Helm
==========

<img src="https://skywalking.apache.org/assets/logo.svg" alt="Sky Walking logo" height="90px" align="right" />

[![GitHub stars](https://img.shields.io/github/stars/apache/skywalking.svg?style=for-the-badge&label=Stars&logo=github)](https://github.com/apache/skywalking)
[![Twitter Follow](https://img.shields.io/twitter/follow/asfskywalking.svg?style=for-the-badge&label=Follow&logo=twitter)](https://twitter.com/AsfSkyWalking)

SkyWalking Kubernetes Helm repository provides ways to install and configure SkyWalking in a Kubernetes cluster.
The scripts are written in Helm 3.

# Documentation

**Full documentation: [skywalking.apache.org/docs/skywalking-helm/next/readme/](https://skywalking.apache.org/docs/skywalking-helm/next/readme/)**
— or read it in this repository under [`docs/`](docs/README.md).

| | |
|---|---|
| Install | [Quick Start](docs/install/quick-start.md) · [Where to Get the Chart](docs/install/chart-sources.md) |
| Storage | [Pick a Backend](docs/storage/choose-a-backend.md) · [Elasticsearch](docs/storage/elasticsearch.md) · [BanyanDB](docs/storage/banyandb.md) · [PostgreSQL](docs/storage/postgresql.md) |
| Web UI | [Horizon UI](docs/ui/horizon-ui.md) · [Set Up Logins](docs/ui/logins.md) · [Configure Horizon](docs/ui/configure.md) |
| Operate | [OAP Init Job](docs/operate/oap-init-job.md) · [Configure OAP](docs/operate/oap-configuration.md) · [Scaling](docs/operate/scaling.md) · [Satellite](docs/operate/satellite.md) |
| Upgrade | [Upgrade](docs/upgrade/upgrading.md) · [Version Compatibility](docs/evaluate/version-compatibility.md) |
| Trouble | [Install and Startup](docs/troubleshooting/install-and-startup.md) · [UI and Login](docs/troubleshooting/ui-and-login.md) |
| Values | [Chart Values](docs/reference/skywalking-chart-values.md) |

# Required values

Three values have no default and must be set explicitly on every install.

| name | description | example |
| ---- | ----------- | ------- |
| `oap.image.tag` | the OAP docker image tag | `11.0.0` |
| `oap.storageType` | the storage type of the OAP | `elasticsearch`, `postgresql`, `banyandb` |
| `ui.image.tag` | the Horizon UI docker image tag | `horizon-1.0.0` |

Set them on the command line, or put them in a values file and pass `-f my-values.yaml`.

# Install

```shell
helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm \
  --version 5.0.0 -n skywalking --create-namespace \
  --set oap.image.tag=11.0.0 \
  --set oap.storageType=banyandb \
  --set ui.image.tag=horizon-1.0.0 \
  --set elasticsearch.enabled=false \
  --set banyandb.enabled=true \
  --set banyandb.image.tag=0.11.0
```

The default storage backend is Elasticsearch, which needs its CRDs installed first — see
[Quick Start](docs/install/quick-start.md) for that path and for the other chart sources
(development snapshots, building from source).

**A fresh install has no login.** Horizon UI ships no default credentials and does not fail closed:
the pod reports Ready and nobody can sign in until you configure users. See
[Set Up Logins](docs/ui/logins.md).

# Contact Us
* Submit an [issue](https://github.com/apache/skywalking/issues)
* Mail list: **dev@skywalking.apache.org**. Mail to `dev-subscribe@skywalking.apache.org`, follow the reply to subscribe the mail list.
* Send `Request to join SkyWalking slack` mail to the mail list(`dev@skywalking.apache.org`), we will invite you in.
* For Chinese speaker, send `[CN] Request to join SkyWalking slack` mail to the mail list(`dev@skywalking.apache.org`), we will invite you in.
* Twitter, [ASFSkyWalking](https://twitter.com/AsfSkyWalking)
* [bilibili B站 视频](https://space.bilibili.com/390683219)

# LICENSE
Apache 2.0
