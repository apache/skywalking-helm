Apache SkyWalking Kubernetes
==========

<img src="http://skywalking.apache.org/assets/logo.svg" alt="Sky Walking logo" height="90px" align="right" />

[![GitHub stars](https://img.shields.io/github/stars/apache/skywalking.svg?style=for-the-badge&label=Stars&logo=github)](https://github.com/apache/skywalking)
[![Twitter Follow](https://img.shields.io/twitter/follow/asfskywalking.svg?style=for-the-badge&label=Follow&logo=twitter)](https://twitter.com/AsfSkyWalking)

SkyWalking Kubernetes repository provides ways to install and configure skywalking in a Kubernetes cluster.
The scripts are written in Helm3.

## Documentation

#### Chart Detailed Configuration
chart detailed configuration please read [Chart Readme](./chart/skywalking/README.md)

#### Deploy SkyWalking and Elasticsearch 7 (default)

```shell script
$ cd chart

$ helm repo add elastic https://helm.elastic.co

$ helm dep up skywalking

$ helm install <release_name> skywalking -n <namespace>
``` 

**Note**: If you want to deploy Elasticsearch 6, execute the following command

```shell script
$ helm dep up skywalking

$ helm install <release_name> skywalking -n <namespace> --values ./skywalking/values-es6.yaml
```

#### Only deploy SkyWalking ,and use existing Elasticsearch
If not want to deploy a new elasticsearch cluster, this way can be solved.

Only need to close the elasticsearch deployed by chart default and configure the existing elasticsearch connection method.

```shell script
$ cd chart

$ helm repo add elastic https://helm.elastic.co

$ helm dep up skywalking

$ helm install <release_name> skywalking -n <namespace> \
        --set elasticsearch.enabled=false \
        --set elasticsearch.config.host=<es_host> \
        --set elasticsearch.config.port.http=<es_port> \
        --set elasticsearch.config.user=<es_user> \
        --set elasticsearch.config.password=<es_password> 
```

**Note**: You need to make sure your ES cluster version is 7.x , If your cluster version is 6.x, execute the following command

```shell script
$ helm dep up skywalking

$ helm install <release_name> skywalking -n <namespace> \
        --values ./skywalking/values-es6.yaml \
        --set elasticsearch.enabled=false \
        --set elasticsearch.config.host=<es_host> \
        --set elasticsearch.config.port.http=<es_port> \
        --set elasticsearch.config.user=<es_user> \
        --set elasticsearch.config.password=<es_password> 
```

## Structure of repository

### helm-chart 

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. 

#### release chart table 
| SkyWalking version | Chart version |
| ------------------ | ------------- |
| 6.5.0              | 1.0.0         |
| 6.6.0              | 1.1.0         | 
| 7.0.0              | 2.0.0         | 
| 8.0.1              | 3.0.0         | 

Please head to the [releases page](http://skywalking.apache.org/downloads/) to download a release of Apache SkyWalking.

Note:  The source code for the release chart matches the git tag.

#### old chart position table

| SkyWalking version | Chart position                                               |
| ------------------ | ------------------------------------------------------------ |
| 6.0.0-GA           | [6.0.0-GA](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.0.0-GA) |
| 6.1.0              | [6.1.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.1.0) |
| 6.3.0              | [6.3.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.3.0) |
| 6.4.0              | [6.4.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.4.0) |

Note:  The source code for old charts are in the **legacy-helm-chart** branch.

# Contact Us
* Submit an [issue](https://github.com/apache/skywalking/issues)
* Mail list: **dev@skywalking.apache.org**. Mail to `dev-subscribe@skywalking.apache.org`, follow the reply to subscribe the mail list.
* Join `skywalking` channel at [Apache Slack](https://join.slack.com/t/the-asf/shared_invite/enQtNzc2ODE3MjI1MDk1LTAyZGJmNTg1NWZhNmVmOWZjMjA2MGUyOGY4MjE5ZGUwOTQxY2Q3MDBmNTM5YTllNGU4M2QyMzQ4M2U4ZjQ5YmY). If the link is not working, find the latest one at [Apache INFRA WIKI](https://cwiki.apache.org/confluence/display/INFRA/Slack+Guest+Invites).
* QQ Group: 392443393(2000/2000, not available), 901167865(available)

# LICENSE
Apache 2.0
