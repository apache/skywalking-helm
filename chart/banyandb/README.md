Apache Skywalking BanyanDB Helm Chart

[Apache Skywalking BanyanDB](https://github.com/apache/skywalking-banyandb/tree/main) is an observability database aims to ingest, analyze and store Metrics, Tracing and Logging data.

## Introduction

This chart bootstraps an Apache Skywalking BanyanDB deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

 - Kubernetes 1.24.0+
 - Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release banyandb -n <namespace>
```

The command deploys BanyanDB on the Kubernetes cluster with the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the banyandb components associated with the chart and deletes the release.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| banyandb.config[0] | string | `"standalone"` |  |
| banyandb.grpcSvc.name | string | `"grpc"` |  |
| banyandb.grpcSvc.port | int | `17912` |  |
| banyandb.grpcSvc.type | string | `"ClusterIP"` |  |
| banyandb.httpSvc.ports[0].name | string | `"http"` |  |
| banyandb.httpSvc.ports[0].port | int | `17913` |  |
| banyandb.httpSvc.ports[1].name | string | `"pprof"` |  |
| banyandb.httpSvc.ports[1].port | int | `6060` |  |
| banyandb.httpSvc.ports[2].name | string | `"observebility"` |  |
| banyandb.httpSvc.ports[2].port | int | `2121` |  |
| banyandb.httpSvc.type | string | `"ClusterIP"` |  |
| banyandb.image.pullPolicy | string | `"IfNotPresent"` |  |
| banyandb.image.repository | string | `"ghcr.io/apache/skywalking-banyandb"` |  |
| banyandb.image.tag | string | `"7443bd36e56404ee813b66a5e2b183d3c9ed3371"` |  |
| banyandb.ingress.annotations."kubernetes.io/ingress-class" | string | `"nginx"` |  |
| banyandb.ingress.enabled | bool | `true` |  |
| banyandb.ingress.hosts[0].host | string | `"localhost"` |  |
| banyandb.ingress.hosts[0].paths[0].path | string | `"/"` |  |
| banyandb.ingress.hosts[0].paths[0].port | int | `17913` |  |
| banyandb.ingress.hosts[0].paths[1].path | string | `"/metrics"` |  |
| banyandb.ingress.hosts[0].paths[1].port | int | `2121` |  |
| banyandb.ingress.hosts[0].paths[2].path | string | `"/debug/pprof"` |  |
| banyandb.ingress.hosts[0].paths[2].port | int | `6060` |  |
| banyandb.ingress.tls | list | `[]` |  |
| banyandb.name | string | `"banyandb"` |  |
| banyandb.podAnnotations.example | string | `"banyandb-foo"` |  |
| banyandb.ports.grpc | int | `17912` |  |
| banyandb.ports.http | int | `17913` |  |
| banyandb.ports.observebility | int | `2121` |  |
| banyandb.ports.pprof | int | `6060` |  |
| banyandb.replicas | int | `1` |  |
| banyandb.securityContext | object | `{}` |  |
| fullnameOverride | string | `""` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| storages.persistentVolumeClaim[0].accessModes[0] | string | `"ReadWriteOnce"` |  |
| storages.persistentVolumeClaim[0].name | string | `"banyandb-metadata"` |  |
| storages.persistentVolumeClaim[0].resources.requests.storage | string | `"5Gi"` |  |
| storages.persistentVolumeClaim[0].volumeMode | string | `"Filesystem"` |  |
| storages.persistentVolumeClaim[1].accessModes[0] | string | `"ReadWriteOnce"` |  |
| storages.persistentVolumeClaim[1].name | string | `"banyandb-measure"` |  |
| storages.persistentVolumeClaim[1].resources.requests.storage | string | `"100Gi"` |  |
| storages.persistentVolumeClaim[1].volumeMode | string | `"Filesystem"` |  |
| storages.persistentVolumeClaim[2].accessModes[0] | string | `"ReadWriteOnce"` |  |
| storages.persistentVolumeClaim[2].name | string | `"banyandb-stream"` |  |
| storages.persistentVolumeClaim[2].resources.requests.storage | string | `"100Gi"` |  |
| storages.persistentVolumeClaim[2].volumeMode | string | `"Filesystem"` |  |
| storages.volume[0].claimName | string | `"banyandb-metadata"` |  |
| storages.volume[0].name | string | `"metadata"` |  |
| storages.volume[0].path | string | `"/tmp/metadata"` |  |
| storages.volume[1].claimName | string | `"banyandb-measure"` |  |
| storages.volume[1].name | string | `"measure"` |  |
| storages.volume[1].path | string | `"/tmp/measure"` |  |
| storages.volume[2].claimName | string | `"banyandb-stream"` |  |
| storages.volume[2].name | string | `"stream"` |  |
| storages.volume[2].path | string | `"/tmp/stream"` |  |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

**Note** You could refer to the [helm install](https://helm.sh/docs/helm/helm_install/) for more command information.

```console
$ helm install myrelease banyandb --set fullnameOverride=newBanyanDB
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install my-release banyandb -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)