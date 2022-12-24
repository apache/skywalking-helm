Apache SWCK Adapter Helm Chart

[Apache SWCK Adapter](https://github.com/apache/skywalking-swck/tree/master/adapter) is a component that provides custom metrics coming from SkyWalking OAP cluster for autoscaling by [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/).

## Introduction

This chart bootstraps a [SWCK Adapter](https://github.com/apache/skywalking-swck/blob/master/docs/custom-metrics-adapter.md) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

 - Kubernetes 1.24.0+ 
 - Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release adapter -n <namespace>
```

The command deploys the adapter on the Kubernetes cluster in the default configuration.  The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the adapter components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the adapter chart and their default values.

| Parameter                                                    | Description                                                                                      | Default                              |
|--------------------------------------------------------------|--------------------------------------------------------------------------------------------------|--------------------------------------|
| `fullnameOverride`                             | Override fullname                                          | `nil`                            |
| `.namespace`               | Namespace of adapter deployment                  | `skywalking-custom-metrics-system` |
| `.replicas`               | The replicas of adapter                                                         | `1`                                |
| `.serviceAccountName`              | The service account name of adapter                                       | `skywalking-custom-metrics-apiserver` |
| `.image.repository` | Adapter container image name                | `docker.io/apache/skywalking-swck` |
| `.image.pullPolicy`               | Adapter container image pull policy                              | `IfNotPresent`                  |
| `.image.tag`             | Adapter container image tag                    | `v0.7.0` |
| `.service.port`                           | The port for the adapter service                                 | `6.1.0`                              |
| `.oap.service.name`          | The service name of OAP                                 | `skywalking-system-oap`  |
| `.oap.service.namespace`                | The service namespace of OAP                          | `skywalking-system`             |
| `.oap.service.port`             | The service port of OAP                                                  | `12800`                              |
| `.resources.limits.cpu`         | The limits of cpu in the adapter                                       | `100m`                              |
| `.resources.limits.memory`       | The limits of memory in the adapter                                                | `200Mi`                      |
| `.resources.requests.cpu`            | The requests of cpu in the adapter | `100m`                  |
| `.resources.requests.memory`       | The requests of memory in the adapter                                  | `200Mi`                        |
| `.affinity`                           | The affinity policy of adapter                                                            | `{}`                                 |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

**Note** You could refer to the [helm install](https://helm.sh/docs/helm/helm_install/) for more command information.

```console
$ helm install myrelease adapter --set fullnameOverride=newadapter
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install my-release adapter -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)
