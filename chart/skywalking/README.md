# Apache Skywalking Helm Chart

[Apache SkyWalking](https://skywalking.apache.org/) is application performance monitor tool for distributed systems,
especially designed for microservices, cloud native and container-based (Docker, K8s, Mesos) architectures.

## Introduction

This chart bootstraps a [Apache SkyWalking](https://skywalking.apache.org/) deployment on
a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

- Kubernetes 1.21+ — the floor its `eck-operator` 3.3.1 and `eck-elasticsearch` 0.18.1
  dependencies declare (both a `kubeVersion` floor of `1.21.0-0`). This chart sets no
  `kubeVersion` of its own, and its templates use only `v1`, `apps/v1`, `batch/v1` and
  `rbac.authorization.k8s.io/v1`, falling back from `networking.k8s.io/v1` Ingress to `v1beta1`
  to `extensions/v1beta1` — so nothing here raises the floor above what ECK asks for.
- Helm 3.8+ — this chart and its BanyanDB dependency are published as OCI artifacts.
- PV dynamic provisioning support on the underlying infrastructure (StorageClass)

## Installing the Chart

There is no default install: three values have no default, and the render fails on each one
independently.

| name | description | example |
| ---- | ----------- | ------- |
| `oap.image.tag` | the OAP docker image tag | `11.0.0` |
| `oap.storageType` | the storage type of the OAP | `elasticsearch`, `postgresql`, `banyandb` |
| `ui.image.tag` | the Horizon UI docker image tag | `horizon-1.0.0` |

`banyandb.image.tag` is required as well whenever the BanyanDB subchart is enabled
(`banyandb.enabled=true`).

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

`elasticsearch.enabled` defaults to `true`, and that path needs the ECK CRDs installed before the
chart — see [Quick Start](../../docs/install/quick-start.md).

**A fresh install has no login.** Horizon UI ships no default credentials and does not fail closed —
the pod reports Ready and nobody can sign in until you configure users. See
[Set Up Logins](../../docs/ui/logins.md).

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `skywalking` deployment:

```shell
$ helm uninstall skywalking -n <namespace>
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

Every value this chart accepts is documented in the values reference:

- on the website: [skywalking Chart Values](https://skywalking.apache.org/docs/skywalking-helm/next/reference/skywalking-chart-values/)
- in this repository: [`docs/reference/skywalking-chart-values.md`](../../docs/reference/skywalking-chart-values.md)

Full documentation for the charts in this repository lives at
[skywalking.apache.org/docs/skywalking-helm](https://skywalking.apache.org/docs/skywalking-helm/next/readme/).
