# Apache Skywalking Helm Chart

[Apache SkyWalking](https://skywalking.apache.org/) is application performance monitor tool for distributed systems, especially designed for microservices, cloud native and container-based (Docker, K8s, Mesos) architectures.

## Introduction

This chart bootstraps a [Apache SkyWalking](https://skywalking.apache.org/) deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

 - Kubernetes 1.9.6+ 
 - PV dynamic provisioning support on the underlying infrastructure (StorageClass)
 - Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release skywalking -n <namespace>
```

The command deploys Apache Skywalking on the Kubernetes cluster in the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the Skywalking chart and their default values.

| Parameter                                                    | Description                                                                                      | Default                              |
|--------------------------------------------------------------|--------------------------------------------------------------------------------------------------|--------------------------------------|
| `nameOverride`                                               | Override name                                                                                    | `nil`                                |
| `serviceAccounts.oap`                                        | Name of the OAP service account to use or create                                                 | `nil`                                |
| `oap.name`                                                   | OAP deployment name                                                                              | `oap`                                |
| `oap.image.repository`                                       | OAP container image name                                                                         | `apache/skywalking-oap-server`       |
| `oap.image.tag`                                              | OAP container image tag                                                                          | `6.1.0`                              |
| `oap.image.pullPolicy`                                       | OAP container image pull policy                                                                  | `IfNotPresent`                       |
| `oap.ports.grpc`                                             | OAP grpc port for tracing or metric                                                              | `11800`                              |
| `oap.ports.rest`                                             | OAP http port for Web UI                                                                         | `12800`                              |
| `oap.replicas`                                               | OAP k8s deployment replicas                                                                      | `2`                                  |
| `oap.service.type`                                           | OAP svc type                                                                                     | `ClusterIP`                          |
| `oap.javaOpts`                                               | Parameters to be added to `JAVA_OPTS`environment variable for OAP                                | `-Xms2g -Xmx2g`                      |
| `oap.antiAffinity`                                           | OAP anti-affinity policy                                                                         | `soft`                               |
| `oap.nodeAffinity`                                           | OAP node affinity policy                                                                         | `{}`                                 |
| `oap.nodeSelector`                                           | OAP labels for master pod assignment                                                             | `{}`                                 |
| `oap.tolerations`                                            | OAP tolerations                                                                                  | `[]`                                 |
| `oap.resources`                                              | OAP node resources requests & limits                                                             | `{} - cpu limit must be an integer`  |
| `oap.envoy.als.enabled`                                      | Open envoy als                                                                                   | `false`                              |
| `oap.env`                                                    | OAP environment variables                                                                        | `[]`                                 |
| `ui.name`                                                    | Web UI deployment name                                                                           | `ui`                                 |
| `ui.replicas`                                                | Web UI k8s deployment replicas                                                                   | `1`                                  |
| `ui.image.repository`                                        | Web UI container image name                                                                      | `apache/skywalking-ui`               |
| `ui.image.tag`                                               | Web UI container image tag                                                                       | `6.1.0`                              |
| `ui.image.pullPolicy`                                        | Web UI container image pull policy                                                               | `IfNotPresent`                       |
| `ui.ingress.enabled`                                         | Create Ingress for Web UI                                                                        | `false`                              |
| `ui.ingress.annotations`                                     | Associate annotations to the Ingress                                                             | `{}`                                 |
| `ui.ingress.path`                                            | Associate path with the Ingress                                                                  | `/`                                  |
| `ui.ingress.hosts`                                           | Associate hosts with the Ingress                                                                 | `[]`                                 |
| `ui.ingress.tls`                                             | Associate TLS with the Ingress                                                                   | `[]`                                 |
| `ui.service.type`                                            | Web UI svc type                                                                                  | `ClusterIP`                          |
| `ui.service.externalPort`                                    | external port for the service                                                                    | `80`                                 |
| `ui.service.internalPort`                                    | internal port for the service                                                                    | `8080`                               |
| `ui.service.externalIPs`                                     | external IP addresses                                                                            | `nil`                                |
| `ui.service.loadBalancerIP`                                  | Load Balancer IP address                                                                         | `nil`                                |
| `ui.service.annotations`                                     | Kubernetes service annotations                                                                   | `{}`                                 |
| `ui.service.loadBalancerSourceRanges`                        | Limit load balancer source IPs to list of CIDRs (where available))                               | `[]`                                 |
| `elasticsearch.enabled`                                      | Spin up a new elasticsearch cluster for SkyWalking                                               | `true`                               |
| `elasticsearch.client.name`                                  |  Client component name                                                                           |  `client`                            |
| `elasticsearch.client.replicas`                              |  Client node replicas (deployment)                                                               |  `2`                                 |
| `elasticsearch.client.resources`                             |  Client node resources requests & limits                                                         |  `{} - cpu limit must be an integer` |
| `elasticsearch.client.priorityClassName`                     |  Client priorityClass                                                                            |  `nil`                               |
| `elasticsearch.client.heapSize`                              |  Client node heap size                                                                           |  `512m`                              |
| `elasticsearch.client.podAnnotations`                        |  Client Deployment annotations                                                                   |  `{}`                                |
| `elasticsearch.client.nodeSelector`                          |  Node labels for client pod assignment                                                           |  `{}`                                |
| `elasticsearch.client.tolerations`                           |  Client tolerations                                                                              |  `[]`                                |
| `elasticsearch.client.serviceAnnotations`                    |  Client Service annotations                                                                      |  `{}`                                |
| `elasticsearch.client.serviceType`                           |  Client service type                                                                             |  `ClusterIP`                         |
| `elasticsearch.client.httpNodePort`                          |  Client service HTTP NodePort port number. Has no effect if client.serviceType is not `NodePort`.|  `nil`                               |
| `elasticsearch.client.loadBalancerIP`                        |  Client loadBalancerIP                                                                           |  `{}`                                |
| `elasticsearch.client.loadBalancerSourceRanges`              |  Client loadBalancerSourceRanges                                                                 |  `{}`                                |
| `elasticsearch.client.antiAffinity`                          |  Client anti-affinity policy                                                                     |  `soft`                              |
| `elasticsearch.client.nodeAffinity`                          |  Client node affinity policy                                                                     |  `{}`                                |
| `elasticsearch.client.initResources`                         |  Client initContainer resources requests & limits                                                |  `{}`                                |
| `elasticsearch.client.additionalJavaOpts`                    |  Parameters to be added to `ES_JAVA_OPTS` environment variable for client                        |  `""`                                |
| `elasticsearch.client.ingress.enabled`                       |  Enable Client Ingress                                                                           |  `false`                             |
| `elasticsearch.client.ingress.user`                          |  If this & password are set, enable basic-auth on ingress                                        |  `nil`                               |
| `elasticsearch.client.ingress.password`                      |  If this & user are set, enable basic-auth on ingress                                            |  `nil`                               |
| `elasticsearch.client.ingress.annotations`                   |  Client Ingress annotations                                                                      |  `{}`                                |
| `elasticsearch.client.ingress.hosts`                         |  Client Ingress Hostnames                                                                        |  `[]`                                |
| `elasticsearch.client.ingress.tls`                           |  Client Ingress TLS configuration                                                                |  `[]`                                |
| `elasticsearch.client.exposeTransportPort`                   |  Expose transport port 9300 on client service (ClusterIP)                                        |  `false`                             |
| `elasticsearch.master.initResources`                         |  Master initContainer resources requests & limits                                                |  `{}`                                |
| `elasticsearch.master.additionalJavaOpts`                    |  Parameters to be added to `ES_JAVA_OPTS` environment variable for master                        |  `""`                                |
| `elasticsearch.master.exposeHttp`                            |  Expose http port 9200 on master Pods for monitoring, etc                                        |  `false`                             |
| `elasticsearch.master.name`                                  |  Master component name                                                                           |  `master`                            |
| `elasticsearch.master.replicas`                              |  Master node replicas (deployment)                                                               |  `2`                                 |
| `elasticsearch.master.resources`                             |  Master node resources requests & limits                                                         |  `{} - cpu limit must be an integer` |
| `elasticsearch.master.priorityClassName`                     |  Master priorityClass                                                                            |  `nil`                               |
| `elasticsearch.master.podAnnotations`                        |  Master Deployment annotations                                                                   |  `{}`                                |
| `elasticsearch.master.nodeSelector`                          |  Node labels for master pod assignment                                                           |  `{}`                                |
| `elasticsearch.master.tolerations`                           |  Master tolerations                                                                              |  `[]`                                |
| `elasticsearch.master.heapSize`                              |  Master node heap size                                                                           |  `512m`                              |
| `elasticsearch.master.name`                                  |  Master component name                                                                           |  `master`                            |
| `elasticsearch.master.persistence.enabled`                   |  Master persistent enabled/disabled                                                              |  `false`                             |
| `elasticsearch.master.persistence.name`                      |  Master statefulset PVC template name                                                            |  `data`                              |
| `elasticsearch.master.persistence.size`                      |  Master persistent volume size                                                                   |  `4Gi`                               |
| `elasticsearch.master.persistence.storageClass`              |  Master persistent volume Class                                                                  |  `nil`                               |
| `elasticsearch.master.persistence.accessMode`                |  Master persistent Access Mode                                                                   |  `ReadWriteOnce`                     |
| `elasticsearch.master.readinessProbe`                        |  Master container readiness probes                                                               |  see `values.yaml` for defaults      |
| `elasticsearch.master.antiAffinity`                          |  Master anti-affinity policy                                                                     |  `soft`                              |
| `elasticsearch.master.nodeAffinity`                          |  Master node affinity policy                                                                     |  `{}`                                |
| `elasticsearch.master.podManagementPolicy`                   |  Master pod creation strategy                                                                    |  `OrderedReady`                      |
| `elasticsearch.master.updateStrategy`                        |  Master node update strategy policy                                                              |  `{type: "onDelete"}`                |
| `elasticsearch.data.initResources`                           |  Data initContainer resources requests & limits                                                  |  `{}`                                |
| `elasticsearch.data.additionalJavaOpts`                      |  Parameters to be added to `ES_JAVA_OPTS` environment variable for data                          |  `""`                                |
| `elasticsearch.data.exposeHttp`                              |  Expose http port 9200 on data Pods for monitoring, etc                                          |  `false`                             |
| `elasticsearch.data.replicas`                                |  Data node replicas (statefulset)                                                                |  `2`                                 |
| `elasticsearch.data.resources`                               |  Data node resources requests & limits                                                           |  `{} - cpu limit must be an integer` |
| `elasticsearch.data.priorityClassName`                       |  Data priorityClass                                                                              |  `nil`                               |
| `elasticsearch.data.heapSize`                                |  Data node heap size                                                                             |  `1536m`                             |
| `elasticsearch.data.hooks.drain.enabled`                     |  Data nodes: Enable drain pre-stop and post-start hook                                           |  `true`                              |
| `elasticsearch.data.persistence.enabled`                     |  Data persistent enabled/disabled                                                                |  `false`                             |
| `elasticsearch.data.persistence.name`                        |  Data statefulset PVC template name                                                              |  `data`                              |
| `elasticsearch.data.persistence.size`                        |  Data persistent volume size                                                                     |  `30Gi`                              |
| `elasticsearch.data.persistence.storageClass`                |  Data persistent volume Class                                                                    |  `nil`                               |
| `elasticsearch.data.persistence.accessMode`                  |  Data persistent Access Mode                                                                     |  `ReadWriteOnce`                     |
| `elasticsearch.data.readinessProbe`                          |  Readiness probes for data-containers                                                            |  see `values.yaml` for defaults      |
| `elasticsearch.data.podAnnotations`                          |  Data StatefulSet annotations                                                                    |  `{}`                                |
| `elasticsearch.data.nodeSelector`                            |  Node labels for data pod assignment                                                             |  `{}`                                |
| `elasticsearch.data.tolerations`                             |  Data tolerations                                                                                |  `[]`                                |
| `elasticsearch.data.terminationGracePeriodSeconds`           |  Data termination grace period (seconds)                                                         |  `3600`                              |
| `elasticsearch.data.antiAffinity`                            |  Data anti-affinity policy                                                                       |  `soft`                              |
| `elasticsearch.data.nodeAffinity`                            |  Data node affinity policy                                                                       |  `{}`                                |
| `elasticsearch.data.podManagementPolicy`                     |  Data pod creation strategy                                                                      |  `OrderedReady`                      |
| `elasticsearch.data.updateStrategy`                          |  Data node update strategy policy                                                                |  `{type: "onDelete"}`                |


Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
$ helm install myrelease skywalking --set nameOverride=newSkywalking
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
$ helm install my-release skywalking -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)

### RBAC Configuration
Roles and RoleBindings resources will be created automatically for `OAP` .

> **Tip**: You can refer to the default `oap-role.yaml` file in [templates](templates/) to customize your own.

### Ingress TLS
If your cluster allows automatic create/retrieve of TLS certificates (e.g. [kube-lego](https://github.com/jetstack/kube-lego)), please refer to the documentation for that mechanism.

To manually configure TLS, first create/retrieve a key & certificate pair for the address(skywalking ui) you wish to protect. Then create a TLS secret in the namespace:

```console
kubectl create secret tls skywalking-tls --cert=path/to/tls.cert --key=path/to/tls.key
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
      - secretName: skywalking-tls
        hosts:
          - skywalking.domain.com
```
### Envoy ALS

Envoy ALS(access log service) provides fully logs about RPC routed, including HTTP and TCP.

If you want to open envoy ALS, you can do this by modifying values.yaml. 

```yaml
oap:
  envoy:
    als:
      enabled: true
```

When envoy als ,will give ServiceAccount clusterrole permission.
More envoy als ,please refer to https://github.com/apache/skywalking/blob/master/docs/en/setup/envoy/als_setting.md#observe-service-mesh-through-als