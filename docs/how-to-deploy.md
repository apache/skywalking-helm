### How to use the SkyWalking Chart?

Two ways:
- deploy SkyWalking and Elasticsearch (default)
- only deploy SkyWalking ,and use existing Elasticsearch

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