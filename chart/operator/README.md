Apache SWCK Operator Helm Chart

[Apache SWCK Operator](https://github.com/apache/skywalking-swck/tree/master/operator) is a platform for the SkyWalking user that provisions, upgrades, maintains SkyWalking relevant components, and makes them work natively on Kubernetes.

## Introduction

This chart bootstraps a [SWCK Operator](https://github.com/apache/skywalking-swck/blob/master/docs/operator.md) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

 - Kubernetes 1.24.0+ 
 - Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release operator -n <namespace>
```

The command deploys the operator on the Kubernetes cluster in the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the operator components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the operator chart and their default values.

| Parameter                    | Description                                                                                                                  | Default                              |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------|--------------------------------------|
| `fullnameOverride`           | Override fullname                                                                                                            | `nil`                                |
| `.replicaCount`              | The replicas of operator                                                                                                     | `1`                                  |
| `.serviceAccountName`        | The service account name of operator                                                                                         | `skywalking-swck-controller-manager` |
| `.image.repository`          | Operator container image name                                                                                                | `docker.io/apache/skywalking-swck`   |
| `.image.pullPolicy`          | Operator container image pull policy                                                                                         | `IfNotPresent`                       |
| `.image.tag`                 | Operator container image tag                                                                                                 | `v0.9.0`                             |
| `.metrics.service.port`      | The port for the operator metrics service                                                                                    | `8443`                               |
| `.webhook.service.port`      | The port for the operator web hook service                                                                                   | `9443`                               |
| `.resources.limits.cpu`      | The limits of cpu in the operator                                                                                            | `200m`                               |
| `.resources.limits.memory`   | The limits of memory in the operator                                                                                         | `300Mi`                              |
| `.resources.requests.cpu`    | The requests of cpu in the operator                                                                                          | `200m`                               |
| `.resources.requests.memory` | The requests of memory in the operator                                                                                       | `300Mi`                              |
| `.affinity`                  | The affinity policy of operator                                                                                              | `{}`                                 |
| `cert-manager.enabled`        | Whether to install demo cert-manager. DO NOT use this in production, this is for quick start.                               | `false`                              |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

**Note** You could refer to the [helm install](https://helm.sh/docs/helm/helm_install/) for more command information.

```console
$ helm install myrelease operator --set fullnameOverride=newoperator
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install my-release operator -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)
