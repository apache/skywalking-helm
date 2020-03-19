#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

CURRENT_DIR="$(cd "$(dirname $0)"; pwd)"

CHART_PATH="$CURRENT_DIR/../../chart"
SKYWALKING_ES7_NAMESPACE="skywaling-es7"
SKYWALKING_ES6_NAMESPACE="skywaling-es6"

ELASTIC_REPO="https://helm.elastic.co/"

cd ${CHART_PATH}

and_elastic_repo(){
  ELASTIC_REPO=$1
  helm repo add elastic ${ELASTIC_REPO}

  STATUS_CMD=`echo $?`
  CHECK_REPO_CMD=`helm repo list | grep ${ELASTIC_REPO} | wc -l`
  echo "$STATUS_CMD"
  echo "$CHECK_REPO_CMD"
  while [[ $STATUS_CMD != 0 && $CHECK_REPO_CMD -ge 1 ]]
  do
    sleep 5
    helm repo add elastic ${ELASTIC_REPO}

    STATUS_CMD=`echo $?`
    CHECK_REPO_CMD=`helm repo list | grep ${ELASTIC_REPO} | wc -l`
  done
}

create_namespace() {
  NAMESPACE=$1
  kubectl create ns ${NAMESPACE}

  STATUS_CMD=`echo $?`
  while [[ $STATUS_CMD != 0 ]]
  do
    sleep 5
    kubectl create ns ${NAMESPACE}
    STATUS_CMD=`echo $?`
  done
}

and_elastic_repo ${ELASTIC_REPO}
create_namespace ${SKYWALKING_ES6_NAMESPACE}
create_namespace ${SKYWALKING_ES7_NAMESPACE}

helm repo up
helm dep up skywalking

sudo sysctl -w vm.max_map_count=262144
sudo sysctl -w vm.drop_caches=1
sudo sysctl -w vm.drop_caches=3

echo "Skywalking ES6 Deploy"
helm -n $SKYWALKING_ES6_NAMESPACE install skywalking skywalking --values ./skywalking/values-es6.yaml --set oap.replicas=1 --set elasticsearch.replicas=1

echo "Skywalking ES7 Deploy"
helm -n $SKYWALKING_ES7_NAMESPACE install skywalking skywalking --set oap.replicas=1 --set elasticsearch.replicas=1

wait_component_available() {
  # shellcheck disable=SC2030
  COMPONENT=&1
  NAMESPACE=$2
  CONDITIONS=$3
  kubectl -n ${NAMESPACE} wait ${COMPONENT} --for condition=${CONDITIONS} --timeout=600s
}

get_component_name() {
  NAME=$1
  NAMESPACE=$2
  COMPONENT_TYPE=$3
  name=${COMPONENT_TYPE}/`kubectl get ${COMPONENT_TYPE} -n ${NAMESPACE} | grep ${NAME} | awk '{print $1}'`
  echo ${name}
}

SW_ES6_DEPLOY_NAME=`get_component_name oap ${SKYWALKING_ES7_NAMESPACE} deploy`

wait_component_available ${SW_ES6_DEPLOY_NAME} ${SKYWALKING_ES7_NAMESPACE} available

#sleep 600
#kubectl -n ${SKYWALKING_ES7_NAMESPACE} wait $component --for condition=available --timeout=600s
#kubectl describe pod/elasticsearch-master-0 -n ${SKYWALKING_ES7_NAMESPACE}
##  kubectl logs elasticsearch-master-0 -n ${SKYWALKING_ES7_NAMESPACE} -f
#kubectl get all -n ${SKYWALKING_ES7_NAMESPACE}
#kubectl -n ${SKYWALKING_ES7_NAMESPACE} wait $component --for condition=available --timeout=600s
#kubectl -n ${SKYWALKING_ES6_NAMESPACE} wait $component --for condition=available --timeout=600s

echo "SkyWalking deployed successfully"
