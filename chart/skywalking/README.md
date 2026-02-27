# Apache Skywalking Helm Chart

[Apache SkyWalking](https://skywalking.apache.org/) is application performance monitor tool for distributed systems,
especially designed for microservices, cloud native and container-based (Docker, K8s, Mesos) architectures.

## Introduction

This chart bootstraps a [Apache SkyWalking](https://skywalking.apache.org/) deployment on
a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

- Kubernetes 1.9.6+
- PV dynamic provisioning support on the underlying infrastructure (StorageClass)
- Helm 3

## Installing the Chart

To install the chart with the release name `my-release`:

```shell
$ helm install my-release skywalking -n <namespace>
```

The command deploys Apache SkyWalking on the Kubernetes cluster in the default configuration.
The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```shell
$ helm uninstall my-release -n <namespace>
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the Skywalking chart and their default values.

| Parameter                              | Description                                                                                                                                                                                                                                                                                                                | Default                                                                                                                  |
|----------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `nameOverride`                         | Override name                                                                                                                                                                                                                                                                                                              | `nil`                                                                                                                    |
| `serviceAccounts.oap.create`           | Create of the OAP service account                                                                                                                                                                                                                                                                                          | `true`                                                                                                                   |
| `serviceAccounts.oap.name`             | Name of the OAP service account to use custom service account when `serviceAccounts.oap.create` is set to false                                                                                                                                                                                                            | ``                                                                                                                       |
| `imagePullSecrets`                     | Image pull secrets                                                                                                                                                                                                                                                                                                         | `[]`                                                                                                                     |
| `oap.name`                             | OAP deployment name                                                                                                                                                                                                                                                                                                        | `oap`                                                                                                                    |
| `oap.dynamicConfig.enabled`            | Enable oap dynamic configuration through k8s configmap                                                                                                                                                                                                                                                                     | `false`                                                                                                                  |
| `oap.dynamicConfig.period`             | Sync period in seconds                                                                                                                                                                                                                                                                                                     | `60`                                                                                                                     |
| `oap.dynamicConfig.config`             | Oap dynamic configuration [documentation](https://github.com/apache/skywalking/blob/master/docs/en/setup/backend/dynamic-config.md)                                                                                                                                                                                        | `{}`                                                                                                                     |
| `oap.image.repository`                 | OAP container image name                                                                                                                                                                                                                                                                                                   | `skywalking.docker.scarf.sh/apache/skywalking-oap-server`                                                                |
| `oap.image.tag`                        | OAP container image tag                                                                                                                                                                                                                                                                                                    | `6.1.0`                                                                                                                  |
| `oap.image.pullPolicy`                 | OAP container image pull policy                                                                                                                                                                                                                                                                                            | `IfNotPresent`                                                                                                           |
| `oap.ports.grpc`                       | OAP grpc port for tracing or metric                                                                                                                                                                                                                                                                                        | `11800`                                                                                                                  |
| `oap.ports.rest`                       | OAP http port for Web UI                                                                                                                                                                                                                                                                                                   | `12800`                                                                                                                  |
| `oap.ports.zipkinreceiver`             | OAP http port for Zipkin receiver(not exposed by default)                                                                                                                                                                                                                                                                  | `9411`                                                                                                                   |
| `oap.ports.zipkinquery`                | OAP http port for querying Zipkin traces and UI(not exposed by default)                                                                                                                                                                                                                                                    | `9412`                                                                                                                   |
| `oap.replicas`                         | OAP k8s deployment replicas                                                                                                                                                                                                                                                                                                | `2`                                                                                                                      |
| `oap.service.type`                     | OAP svc type                                                                                                                                                                                                                                                                                                               | `ClusterIP`                                                                                                              |
| `oap.service.annotations`              | OAP svc annotations                                                                                                                                                                                                                                                                                                        | `{}`                                                                                                                     |
| `oap.javaOpts`                         | Parameters to be added to `JAVA_OPTS`environment variable for OAP                                                                                                                                                                                                                                                          | `-Xms2g -Xmx2g`                                                                                                          |
| `oap.antiAffinity`                     | OAP anti-affinity policy                                                                                                                                                                                                                                                                                                   | `soft`                                                                                                                   |
| `oap.nodeAffinity`                     | OAP node affinity policy                                                                                                                                                                                                                                                                                                   | `{}`                                                                                                                     |
| `oap.nodeSelector`                     | OAP labels for master pod assignment                                                                                                                                                                                                                                                                                       | `{}`                                                                                                                     |
| `oap.tolerations`                      | OAP tolerations                                                                                                                                                                                                                                                                                                            | `[]`                                                                                                                     |
| `oap.resources`                        | OAP node resources requests & limits                                                                                                                                                                                                                                                                                       | `{} - cpu limit must be an integer`                                                                                      |
| `oap.startupProbe`                     | Configuration fields for the [startupProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)                                                                                                                                                                         | `tcpSocket.port: 12800` <br> `failureThreshold: 9` <br> `periodSeconds: 10`                                              
| `oap.livenessProbe`                    | Configuration fields for the [livenessProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)                                                                                                                                                                        | `tcpSocket.port: 12800` <br> `initialDelaySeconds: 5` <br> `periodSeconds: 10`                                           
| `oap.readinessProbe`                   | Configuration fields for the [readinessProbe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)                                                                                                                                                                       | `tcpSocket.port: 12800` <br> `initialDelaySeconds: 5` <br> `periodSeconds: 10`                                           
| `oap.env`                              | OAP environment variables                                                                                                                                                                                                                                                                                                  | `[]`                                                                                                                     |
| `oap.securityContext`                  | Allows you to set the [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) for the pod                                                                                                                                                         | `fsGroup: 1000`<br>`runAsUser: 1000`                                                                                     |
| `ui.name`                              | Web UI deployment name                                                                                                                                                                                                                                                                                                     | `ui`                                                                                                                     |
| `ui.replicas`                          | Web UI k8s deployment replicas                                                                                                                                                                                                                                                                                             | `1`                                                                                                                      |
| `ui.image.repository`                  | Web UI container image name                                                                                                                                                                                                                                                                                                | `skywalking.docker.scarf.sh/apache/skywalking-ui`                                                                        |
| `ui.image.tag`                         | Web UI container image tag                                                                                                                                                                                                                                                                                                 | `6.1.0`                                                                                                                  |
| `ui.image.pullPolicy`                  | Web UI container image pull policy                                                                                                                                                                                                                                                                                         | `IfNotPresent`                                                                                                           |
| `ui.nodeAffinity`                      | Web UI node affinity policy                                                                                                                                                                                                                                                                                                | `{}`                                                                                                                     |
| `ui.nodeSelector`                      | Web UI labels for pod assignment                                                                                                                                                                                                                                                                                           | `{}`                                                                                                                     |
| `ui.tolerations`                       | Web UI tolerations                                                                                                                                                                                                                                                                                                         | `[]`                                                                                                                     |
| `ui.ingress.enabled`                   | Create Ingress for Web UI                                                                                                                                                                                                                                                                                                  | `false`                                                                                                                  |
| `ui.ingress.annotations`               | Associate annotations to the Ingress                                                                                                                                                                                                                                                                                       | `{}`                                                                                                                     |
| `ui.ingress.path`                      | Associate path with the Ingress                                                                                                                                                                                                                                                                                            | `/`                                                                                                                      |
| `ui.ingress.hosts`                     | Associate hosts with the Ingress                                                                                                                                                                                                                                                                                           | `[]`                                                                                                                     |
| `ui.ingress.tls`                       | Associate TLS with the Ingress                                                                                                                                                                                                                                                                                             | `[]`                                                                                                                     |
| `ui.service.type`                      | Web UI svc type                                                                                                                                                                                                                                                                                                            | `ClusterIP`                                                                                                              |
| `ui.service.externalPort`              | external port for the service                                                                                                                                                                                                                                                                                              | `80`                                                                                                                     |
| `ui.service.internalPort`              | internal port for the service                                                                                                                                                                                                                                                                                              | `8080`                                                                                                                   |
| `ui.service.externalIPs`               | external IP addresses                                                                                                                                                                                                                                                                                                      | `nil`                                                                                                                    |
| `ui.service.loadBalancerIP`            | Load Balancer IP address                                                                                                                                                                                                                                                                                                   | `nil`                                                                                                                    |
| `ui.service.annotations`               | Kubernetes service annotations                                                                                                                                                                                                                                                                                             | `{}`                                                                                                                     |
| `ui.service.loadBalancerSourceRanges`  | Limit load balancer source IPs to list of CIDRs (where available))                                                                                                                                                                                                                                                         | `[]`                                                                                                                     |
| `ui.securityContext`                   | Allows you to set the [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) for the pod                                                                                                                                                         | `fsGroup: 1000`<br>`runAsUser: 1000`                                                                                     |
| `oapInit.nodeAffinity`                 | OAP init job node affinity policy                                                                                                                                                                                                                                                                                          | `{}`                                                                                                                     |
| `oapInit.nodeSelector`                 | OAP init job labels for master pod assignment                                                                                                                                                                                                                                                                              | `{}`                                                                                                                     |
| `oapInit.tolerations`                  | OAP init job tolerations                                                                                                                                                                                                                                                                                                   | `[]`                                                                                                                     |
| `oapInit.extraPodLabels`               | OAP init job metadata labels                                                                                                                                                                                                                                                                                               | `[]`                                                                                                                     |
| `satellite.name`                       | Satellite deployment name                                                                                                                                                                                                                                                                                                  | `satellite`                                                                                                              |
| `satellite.replicas`                   | Satellite k8s deployment replicas                                                                                                                                                                                                                                                                                          | `1`                                                                                                                      |
| `satellite.enabled`                    | Is enable Satellite                                                                                                                                                                                                                                                                                                        | `false`                                                                                                                  |
| `satellite.image.repository`           | Satellite container image name                                                                                                                                                                                                                                                                                             | `skywalking.docker.scarf.sh/apache/skywalking-satellite`                                                                 |
| `satellite.image.tag`                  | Satellite container image tag                                                                                                                                                                                                                                                                                              | `v0.4.0`                                                                                                                 |
| `satellite.image.pullPolicy`           | Satellite container image pull policy                                                                                                                                                                                                                                                                                      | `IfNotPresent`                                                                                                           |
| `satellite.antiAffinity`               | Satellite anti-affinity policy                                                                                                                                                                                                                                                                                             | `soft`                                                                                                                   |
| `satellite.nodeAffinity`               | Satellite node affinity policy                                                                                                                                                                                                                                                                                             | `{}`                                                                                                                     |
| `satellite.nodeSelector`               | Satellite labels for pod assignment                                                                                                                                                                                                                                                                                        | `{}`                                                                                                                     |
| `satellite.tolerations`                | Satellite tolerations                                                                                                                                                                                                                                                                                                      | `[]`                                                                                                                     |
| `satellite.service.type`               | Satellite svc type                                                                                                                                                                                                                                                                                                         | `ClusterIP`                                                                                                              |
| `satellite.ports.grpc`                 | Satellite grpc port for tracing, metrics, logs, events                                                                                                                                                                                                                                                                     | `11800`                                                                                                                  |
| `satellite.ports.prometheus`           | Satellite http port for Prometheus monitoring                                                                                                                                                                                                                                                                              | `1234`                                                                                                                   |
| `satellite.resources`                  | Satellite node resources requests & limits                                                                                                                                                                                                                                                                                 | `{} - cpu limit must be an integer`                                                                                      |
| `satellite.podAnnotations`             | Configurable [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/) applied to all Satellite pods                                                                                                                                                                                   | `{}`                                                                                                                     |
| `satellite.env`                        | Satellite environment variables                                                                                                                                                                                                                                                                                            | `[]`                                                                                                                     |
| `satellite.securityContext`            | Allows you to set the [securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) for the pod                                                                                                                                                         | `fsGroup: 1000`<br>`runAsUser: 1000`                                                                                     |

### Elasticsearch (ECK)

Elasticsearch is deployed via [ECK (Elastic Cloud on Kubernetes)](https://github.com/elastic/cloud-on-k8s).
The chart includes the ECK operator and an `eck-elasticsearch` subchart. Set `eckOperator.enabled=false` if the ECK operator is already installed in your cluster.

#### Top-level parameters

| Parameter | Description | Default |
|---|---|---|
| `eckOperator.enabled` | Deploy the ECK operator | `true` |
| `elasticsearch.enabled` | Deploy an ECK-managed Elasticsearch cluster | `true` |
| `elasticsearch.version` | Elasticsearch version to deploy | `8.18.8` |
| `elasticsearch.fullnameOverride` | Override the Elasticsearch resource name. The ECK service will be `{name}-es-http` | `""` |
| `elasticsearch.labels` | Labels applied to the Elasticsearch resource | `{}` |
| `elasticsearch.annotations` | Annotations applied to the Elasticsearch resource | `{}` |
| `elasticsearch.http` | HTTP layer settings. TLS is disabled by default for OAP connectivity | `tls.selfSignedCertificate.disabled: true` |
| `elasticsearch.secureSettings` | [Secure settings](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-es-secure-settings.html) to inject from Kubernetes secrets | `[]` |
| `elasticsearch.updateStrategy` | [Update strategy](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-update-strategy.html) controlling simultaneous changes | `{}` |
| `elasticsearch.volumeClaimDeletePolicy` | Policy for PVC deletion on scale-down or cluster deletion | `""` |
| `elasticsearch.ingress.enabled` | Enable ingress to expose Elasticsearch externally | `false` |

#### External Elasticsearch (when `elasticsearch.enabled` is `false`)

| Parameter | Description | Default |
|---|---|---|
| `elasticsearch.config.host` | Elasticsearch host | `elasticsearch` |
| `elasticsearch.config.port.http` | Elasticsearch HTTP port | `9200` |
| `elasticsearch.config.user` | Elasticsearch user (optional) | `""` |
| `elasticsearch.config.password` | Elasticsearch password (optional) | `""` |

#### Node sets (`elasticsearch.nodeSets[]`)

ECK [node sets](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-node-configuration.html) define the topology of the Elasticsearch cluster. Each entry in the list creates a group of Elasticsearch nodes.

| Parameter | Description | Default |
|---|---|---|
| `nodeSets[].name` | Name of the node set | `default` |
| `nodeSets[].count` | Number of Elasticsearch nodes in this set | `3` |
| `nodeSets[].config` | Elasticsearch configuration (e.g. `node.store.allow_mmap`, `node.roles`) | `node.store.allow_mmap: false` |
| `nodeSets[].volumeClaimTemplates` | Persistent storage for Elasticsearch data | `[]` (ECK default: EmptyDir) |

#### Pod template (`elasticsearch.nodeSets[].podTemplate`)

The pod template follows standard Kubernetes Pod spec nested under `podTemplate.spec`. This controls scheduling, resources, init containers, etc.

| Parameter | Description | Default |
|---|---|---|
| `podTemplate.metadata.annotations` | Pod annotations (e.g. `iam.amazonaws.com/role`) | `{}` |
| `podTemplate.metadata.labels` | Extra pod labels | `{}` |
| `podTemplate.spec.affinity` | Pod [affinity](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-advanced-node-scheduling.html) rules | not set |
| `podTemplate.spec.nodeSelector` | Node selector for pod assignment | not set |
| `podTemplate.spec.tolerations` | Pod tolerations | not set |
| `podTemplate.spec.imagePullSecrets` | Image pull secrets | not set |
| `podTemplate.spec.priorityClassName` | Priority class name | not set |
| `podTemplate.spec.terminationGracePeriodSeconds` | Grace period for pod termination | not set |
| `podTemplate.spec.initContainers` | Init containers (e.g. sysctl `vm.max_map_count`) | not set |
| `podTemplate.spec.containers[].resources` | Container resource requests & limits | `requests: 100m cpu, 2Gi mem` <br> `limits: 2Gi mem` |
| `podTemplate.spec.containers[].env` | Environment variables (e.g. `ES_JAVA_OPTS`) | not set |
| `podTemplate.spec.containers[].securityContext` | Container-level security context | not set (ECK managed) |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
$ helm install myrelease skywalking --set nameOverride=newSkywalking
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the
chart. For example,

```console
$ helm install my-release skywalking -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)

### RBAC Configuration

Roles and RoleBindings resources will be created automatically for `OAP` .

> **Tip**: You can refer to the default `oap-role.yaml` file in [templates](templates/) to customize your own.

### Ingress TLS

If your cluster allows automatic create/retrieve of TLS certificates (
e.g. [kube-lego](https://github.com/jetstack/kube-lego)), please refer to the documentation for that mechanism.

To manually configure TLS, first create/retrieve a key & certificate pair for the address(skywalking ui) you wish to
protect. Then create a TLS secret in the namespace:

```console
kubectl create secret tls skywalking-tls --cert=path/to/tls.cert --key=path/to/tls.key
```

Include the secret's name, along with the desired hostnames, in the skywalking-ui Ingress TLS section of your
custom `values.yaml` file:

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
      - skywalking

    ## Skywalking ui server Ingress TLS configuration
    ## Secrets must be manually created in the namespace
    ##
    tls:
      - secretName: skywalking
        hosts:
          - skywalking
```

### Envoy ALS

Envoy ALS(access log service) provides fully logs about RPC routed, including HTTP and TCP.

If you want to open envoy ALS, you can do this by modifying values.yaml. default open.

```yaml
serviceAccounts:
  oap:
    create: true
```

When envoy als ,will give ServiceAccount clusterrole permission.
More envoy als ,please refer
to https://github.com/apache/skywalking/blob/master/docs/en/setup/envoy/als_setting.md#observe-service-mesh-through-als
