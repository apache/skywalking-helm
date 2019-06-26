# Skywalking Helm Charts

[Apache SkyWalking](https://skywalking.apache.org/) is application performance monitor tool for distributed systems, especially designed for microservices, cloud native and container-based (Docker, K8s, Mesos) architectures.

## Introduction

This chart bootstraps a [Apache SkyWalking](https://skywalking.apache.org/) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

- Kubernetes 1.9.6+ 

## Installing the Chart

To install the chart with the release name `my-release`:

```console
$ helm install --name my-release skywalking
```

The command deploys Skywalking on the Kubernetes cluster in the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```console
$ helm delete my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the Skywalking chart and their default values.

Parameter | Description | Default
--------- | ----------- | -------
`elasticsearch.name` | ES statefulset name | `skywalking-elasticsearch` 
 `elasticsearch.replicas`                      | ES k8s statefulset replicas | `3` 
`elasticsearch.image.repository` | ES container image name | `docker.elastic.co/elasticsearch/elasticsearch-oss` 
`elasticsearch.image.tag` | ES container image tag | `6.3.2` 
`elasticsearch.image.pullPolicy` | ES container image pull policy | `IfNotPresent`
`elasticsearch.ports.http` | Expose http port 9200 on es Pods for skywalking-oap | `9200` 
`elasticsearch.ports.tcp` | Expose tcp port 9300 on es Pods | `9300` 
`elasticsearch.env.esJavaOpts` | Parameters to be added to `ES_JAVA_OPTS`environment variable for ES | `"-Xms4g -Xmx4g"` 
`elasticsearch.resources` | ES node resources requests & limits | `requests.memory=8Gi，limits.memory=16Gi - cpu limit must be an integer` 
`elasticsearch.persistence.enabled` | ES persistent enabled/disabled | `true` 
`elasticsearch.persistence.storageClass` | ES persistent volume Class | `fast` 
`elasticsearch.persistence.accessMode` | Master persistent Access Mode | `ReadWriteOnce` 
 `elasticsearch.persistence.size`              | Master persistent Access size | `30Gi` 
`elasticsearch.terminationGracePeriodSeconds` | ES termination grace period (seconds) | `300` 
`oap.name` | OAP deployment name | `skywalking-oap` 
`oap.image.repository` | OAP container image name | `apache/skywalking-oap-server` 
`oap.image.tag` | OAP container image tag | `6.0.0-GA` 
`oap.image.pullPolicy` | OAP container image pull policy | `IfNotPresent` 
`oap.ports.grpc` | OAP grpc port for tracing or metric | `11800` 
`oap.ports.rest` | OAP http port for Web UI | `12800` 
`oap.replicas` | OAP k8s deployment replicas | `3` 
`oap.service.type` | OAP svc type | `ClusterIP` 
`oap.env.javaOpts` | Parameters to be added to `JAVA_OPTS`environment variable for OAP | `-Xms256M -Xmx512M` 
`oap.resources` | OAP node resources requests & limits | `requests.memory=1Gi，limits.memory=2Gi - cpu limit must be an integer` 
`ui.name` | Web UI deployment name | `skywalking-ui` 
`ui.replicas` | Web UI k8s deployment replicas | `1` 
`ui.image.repository` | Web UI container image name | `apache/skywalking-ui` 
`ui.image.tag` | Web UI container image tag | `6.0.0-GA` 
 `ui.image.pullPolicy`                         | Web UI container image pull policy | `IfNotPresent` 
`ui.ports.page` | Web UI http port | `8080` 
`ui.ingress.enabled` | Create Ingress for Skywalking Web UI | `false` 
`ui.ingress.annotations` | Associate annotations to the Ingress | `{}`
`ui.ingress.path` | Associate hosts with the Ingress | `/` 
`ui.ingress.hosts` | Associate hosts with the Ingress | `[]` 
`ui.ingress.tls` | Associate TLS with the Ingress | `[]` 
 `ui.service.type`                             | Web UI svc type | `NodePort` 
 `ui.resources`                  | Web UI node resources requests & limits | `requests.memory=8Gi，limits.memory=16Gi - cpu limit must be an integer` 
 `TZ` | Time zone configuration to OAP and Web UI | `UTC+0` 

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
$ helm install skywalking  --name=myrelease --set elasticsearch.terminationGracePeriodSeconds=360
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install skywalking --name my-release -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)

### RBAC Configuration
Roles and RoleBindings resources will be created automatically for `OAP` .

> **Tip**: You can refer to the default `oap-role.yaml` file in [templates](templates/) to customize your own.

### ConfigMap Files
Skywalking is configured through [oap-config.yaml](oap-config.yaml). This file (and any others listed in `Files`) will be mounted into the `skywalking-oap` pod.

### Ingress TLS
If your cluster allows automatic create/retrieve of TLS certificates (e.g. [kube-lego](https://github.com/jetstack/kube-lego)), please refer to the documentation for that mechanism.

To manually configure TLS, first create/retrieve a key & certificate pair for the address(skywalking ui) you wish to protect. Then create a TLS secret in the namespace:

```console
kubectl create secret tls skywalking-ui-server-tls --cert=path/to/tls.cert --key=path/to/tls.key
```

Include the secret's name, along with the desired hostnames, in the skywalking-ui Ingress TLS section of your custom `values.yaml` file:

```yaml
ui:
  ingress:
    ## If true, Skywalking ui server Ingress will be created
    ##
    enabled: true

    ## Skywalking ui server Ingress hostnames
    ## Must be provided if Ingress is enabled
    ##
    hosts:
      - skywalking.domain.com

    ## Skywalking ui server Ingress TLS configuration
    ## Secrets must be manually created in the namespace
    ##
    tls:
      - secretName: skywalking-ui-server-tls
        hosts:
          - skywalking.domain.com
```
