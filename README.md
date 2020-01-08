Apache SkyWalking Kubernetes
==========

# Deploy SkyWalking backend to Kubernetes cluster

To install and configure skywalking in a Kubernetes cluster, follow these instructions.

## Documentation
#### Deploy SkyWalking and Elasticsearch 7 (default)

```shell script
$ cd chart

$ helm repo add stable https://kubernetes-charts.storage.googleapis.com/

$ helm dep up skywalking-es7

$ helm install <release_name> skywalking-es7 -n <namespace>
``` 

**Note**: If you want to deploy Elasticsearch 6, execute the following command

```shell script
$ helm dep up skywalking-es6

$ helm install <release_name> skywalking-es6 -n <namespace>
```

#### Only deploy SkyWalking ,and use existing Elasticsearch
If not want to deploy a new elasticsearch cluster, this way can be solved.

Only need to close the elasticsearch deployed by chart default and configure the existing elasticsearch connection method.

```shell script
$ cd chart

$ helm repo add stable https://kubernetes-charts.storage.googleapis.com/

$ helm dep up skywalking-es7

$ helm install <release_name> skywalking-es7 -n <namespace> \
        --set elasticsearch.enabled=false \
        --set elasticsearch.config.host=<es_host> \
        --set elasticsearch.config.port.http=<es_port>
```

**Note**: You need to make sure your ES cluster version is 7.x , If your cluster version is 6.x, execute the following command

```shell script
$ helm dep up skywalking-es6

$ helm install <release_name> skywalking-es6 -n <namespace> \
        --set elasticsearch.enabled=false \
        --set elasticsearch.config.host=<es_host> \
        --set elasticsearch.config.port.http=<es_port>
```

## Structure of repository

### helm-chart 

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. 

#### release chart table 
| SkyWalking version | Chart name     | Chart version |
| ------------------ | -------------  | ------------- |
| 6.5.0              | skywalking     | 1.0.0         |
| 6.6.0-es6          | skywalking-es6 | 1.1.0         |
| 6.6.0-es7          | skywalking-es7 | 1.1.0         | 

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
