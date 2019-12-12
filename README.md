Apache SkyWalking Kubernetes
==========

# Deploy SkyWalking backend to Kubernetes cluster

To install and configure skywalking in a Kubernetes cluster, follow these instructions.

## Documentation
#### Deploy SkyWalking and Elasticsearch (default)

```shell script
$ cd chart

$ helm add stable https://kubernetes-charts.storage.googleapis.com/

$ helm dep up 

$ helm install <release_name> skywalking -n <namespace>
```

#### Only deploy SkyWalking ,and use existing Elasticsearch
If not want to deploy a new elasticsearch cluster, this way can be solved.

Only need to close the elasticsearch deployed by chart default and configure the existing elasticsearch connection method.

```shell script
$ cd chart

$ helm add stable https://kubernetes-charts.storage.googleapis.com/

$ helm dep up 

$ helm install <release_name> skywalking -n <namespace> \
        --set elasticsearch.enabled=false \
        --set elasticsearch.config.host=<es_host> \
        --set elasticsearch.config.port.http=<es_port>
```

## Structure of repository

### helm-chart 

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. 

#### release chart table 
| SkyWalking version | Chart version |
| ------------------ | ------------- |
| 6.5.0              | 1.0.0         |

Note:  The source code for the release chart is located in the chart folder in the master branch.

#### old chart position table

| SkyWalking version | Chart position                                               |
| ------------------ | ------------------------------------------------------------ |
| 6.0.0-GA           | [6.0.0-GA](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.0.0-GA) |
| 6.1.0              | [6.1.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.1.0) |
| 6.3.0              | [6.3.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.3.0) |
| 6.4.0              | [6.4.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.4.0) |

Note:  The source code for old charts are in the **legacy-helm-chart** branch.

# LICENSE
Apache 2.0
