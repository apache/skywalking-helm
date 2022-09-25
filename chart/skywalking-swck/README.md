Apache Skywalking-SWCK Helm Chart

[Apache Skywalking-SWCK](https://github.com/apache/skywalking-swck) is a platform for the SkyWalking user that provisions, upgrades, maintains SkyWalking relevant components, and makes them work natively on Kubernetes.

## Introduction

This chart bootstraps a [SWCK Operator](https://github.com/apache/skywalking-swck/blob/master/docs/operator.md) deployment and a [SWCK Adapter](https://github.com/apache/skywalking-swck/blob/master/docs/custom-metrics-adapter.md) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

 - Kubernetes 1.24.0+ 
 - Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release skywalking-swck -n <namespace>
```

The command deploys Apache SkyWalking-SWCK on the Kubernetes cluster in the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the SkyWalking-SWCK components associated with the chart and deletes the release.

## Configuration

There are two major components in swck, namely operator and custom metrics adapter. The following table lists the configurable parameters of the two components and their default values.

| Parameter                                                    | Description                                                                                      | Default                              |
|--------------------------------------------------------------|--------------------------------------------------------------------------------------------------|--------------------------------------|
| `fullnameOverride`                             | Override fullname                                          | `nil`                            |
| `adapter.enabled`                             | Enable the custom metrics adapter.                                          | `false`                            |
| `adapter.namespace`               | Namespace of adapter deployment                  | `skywalking-custom-metrics-system` |
| `adapter.replicaCount`               | The replicas of adapter                                                         | `1`                                |
| `adapter.serviceAccountName`              | The service account name of adapter                                       | `skywalking-custom-metrics-apiserver` |
| `adapter.image.repository` | Adapter container image name                | `docker.io/apache/skywalking-swck` |
| `adapter.image.pullPolicy`               | Adapter container image pull policy                              | `IfNotPresent`                  |
| `adapter.image.tag`             | Adapter container image tag                    | `v0.7.0` |
| `adapter.service.port`                           | The port for the adapter service                                 | `6.1.0`                              |
| `adapter.oap.service.name`          | The service name of OAP                                 | `skywalking-system-oap`  |
| `adapter.oap.service.namespace`                | The service namespace of OAP                          | `skywalking-system`             |
| `adapter.oap.service.port`             | The service port of OAP                                                  | `12800`                              |
| `adapter.resources.limits.cpu`         | The limits of cpu in the adapter                                       | `100m`                              |
| `adapter.resources.limits.memory`       | The limits of memory in the adapter                                                | `200Mi`                      |
| `adapter.resources.requests.cpu`            | The requests of cpu in the adapter | `100m`                  |
| `adapter.resources.requests.memory`       | The requests of memory in the adapter                                  | `200Mi`                        |
| `adapter.affinity`                           | The affinity policy of adapter                                                            | `{}`                                 |
| `operator.replicaCount`                | The replicas of operator                               | `1`                                |
| `operator.serviceAccountName`     | The service account name of operator                                        | `skywalking-swck-controller-manager` |
| `operator.image.repository`               | Operator container image name                          | `docker.io/apache/skywalking-swck` |
| `operator.image.pullPolicy`    | Operator container image pull policy                                        | `IfNotPresent`                  |
| `operator.image.tag`                         | Operator container image tag                                     | `v0.7.0`                           |
| `operator.metrics.service.port`              | The port for the operator metrics service                           | `8443`                             |
| `operator.webhook.service.port`             | The port for the operator web hook service                   | `9443`                              |
| `operator.resources.limits.cpu`      | The limits of cpu in the operator          | `200m`                                |
| `operator.resources.limits.memory`   | The limits of memory in the operator       | `300Mi`                               |
| `operator.resources.requests.cpu`    | The requests of cpu in the operator        | `200m`                                |
| `operator.resources.requests.memory` | The requests of memory in the operator     | `300Mi`                        |
| `operator.affinity`                   | The affinity policy of operator                            | `{}`                                 |


Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
$ helm install myrelease skywalking-swck --set fullnameOverride=newskywalking-swck --set adapter.enabled=true
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install my-release skywalking-swck -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)
