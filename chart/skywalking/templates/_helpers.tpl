{{/*
Licensed to the Apache Software Foundation (ASF) under one or more
contributor license agreements.  See the NOTICE file distributed with
this work for additional information regarding copyright ownership.
The ASF licenses this file to You under the Apache License, Version 2.0
(the "License"); you may not use this file except in compliance with
the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "skywalking.name" -}}
{{- default .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "skywalking.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified oap name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "skywalking.oap.fullname" -}}
{{ template "skywalking.fullname" . }}-{{ .Values.oap.name }}
{{- end -}}

{{/*
Create a oap full labels value.
*/}}
{{- define "skywalking.oap.labels" -}}
app={{ template "skywalking.name" . }},release={{ .Release.Name }},component={{ .Values.oap.name }}
{{- end -}}

{{/*
Create a default fully qualified ui name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "skywalking.ui.fullname" -}}
{{ template "skywalking.fullname" . }}-{{ .Values.ui.name }}
{{- end -}}

{{/*
Create a default fully qualified satellite name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "skywalking.satellite.fullname" -}}
{{ template "skywalking.fullname" . }}-{{ .Values.satellite.name }}
{{- end -}}

{{/*
Create the name of the service account to use for the oap cluster
*/}}
{{- define "skywalking.serviceAccountName.oap" -}}
{{- if .Values.serviceAccounts.oap.create -}}
    {{ default (include "skywalking.oap.fullname" .) .Values.serviceAccounts.oap.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccounts.oap.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use for the satellite cluster
*/}}
{{- define "skywalking.serviceAccountName.satellite" -}}
{{ default (include "skywalking.satellite.fullname" .) .Values.serviceAccounts.satellite }}
{{- end -}}

{{- define "skywalking.containers.wait-for-storage" -}}
{{- if eq .Values.oap.storageType "elasticsearch" }}
- name: wait-for-elasticsearch
  image: {{ .Values.initContainer.image }}:{{ .Values.initContainer.tag }}
  imagePullPolicy: IfNotPresent
    {{- if .Values.elasticsearch.enabled }}
  command: ['sh', '-c', 'for i in $(seq 1 60); do nc -z -w3 {{ .Values.elasticsearch.clusterName }}-{{ .Values.elasticsearch.nodeGroup }} {{ .Values.elasticsearch.httpPort }} && exit 0 || sleep 5; done; exit 1']
    {{- else }}
  command: ['sh', '-c', 'for i in $(seq 1 60); do nc -z -w3 {{ .Values.elasticsearch.config.host }} {{ .Values.elasticsearch.config.port.http }} && exit 0 || sleep 5; done; exit 1']
    {{- end }}
{{- else if eq .Values.oap.storageType "postgresql" -}}
- name: wait-for-postgresql
  image: postgres:13
  imagePullPolicy: IfNotPresent
  command:
    - sh
    - -c
    - |
    {{- if .Values.postgresql.enabled }}
      until pg_isready -h '{{ template "skywalking.name" . }}-postgresql' -p '{{ .Values.postgresql.containerPorts.postgresql }}' -U '{{ .Values.postgresql.auth.username }}'; do
    {{- else }}
      until pg_isready -h '{{ .Values.postgresql.config.host }}' -p '{{ .Values.postgresql.containerPorts.postgresql }}' -U '{{ .Values.postgresql.auth.username }}'; do
    {{- end }}
        echo "Waiting for postgresql..."
        sleep 3
      done
{{- else if eq .Values.oap.storageType "banyandb" -}}
{{- $address := .Values.banyandb.config.httpAddress -}}
{{- if .Values.banyandb.enabled -}}
{{- $address = printf "%s-http:%s" (include "skywalking.banyandb.fullname" .) (include "skywalking.banyandb.httpPort" .) -}}
{{- end }}
- name: wait-for-banyandb
  image: curlimages/curl
  imagePullPolicy: IfNotPresent
  command: ['sh', '-c', 'for i in $(seq 1 60); do curl -k {{ $address }}/api/healthz && exit 0 || sleep 5; done; exit 1']
{{- end }}
{{- end -}}

# Storage-related environment variables are defined here.
{{- define "skywalking.oap.envs.storage" -}}
- name: SW_STORAGE
  value: {{ required "oap.storageType is required" .Values.oap.storageType }}
{{- if eq .Values.oap.storageType "elasticsearch" }}
- name: SW_STORAGE_ES_CLUSTER_NODES
  {{- if .Values.elasticsearch.enabled }}
  value: "{{ .Values.elasticsearch.clusterName }}-{{ .Values.elasticsearch.nodeGroup }}:{{ .Values.elasticsearch.httpPort }}"
  {{- else }}
  value: "{{ .Values.elasticsearch.config.host }}:{{ .Values.elasticsearch.config.port.http }}"
  {{- end }}
  {{- if not .Values.elasticsearch.enabled }}
    {{- if .Values.elasticsearch.config.user }}
- name: SW_ES_USER
  value: "{{ .Values.elasticsearch.config.user }}"
    {{- end }}
    {{- if .Values.elasticsearch.config.password }}
- name: SW_ES_PASSWORD
  value: "{{ .Values.elasticsearch.config.password }}"
    {{- end }}
  {{- end }}
{{- else if eq .Values.oap.storageType "postgresql" }}
{{- $postgresqlHost := print (include "skywalking.name" .) "-postgresql" -}}
{{- if not .Values.postgresql.enabled -}}
{{- $postgresqlHost = .Values.postgresql.config.host -}}
{{- end }}
- name: SW_JDBC_URL
  value: "jdbc:postgresql://{{ $postgresqlHost }}:{{ .Values.postgresql.containerPorts.postgresql }}/{{ .Values.postgresql.auth.database }}"
- name: SW_DATA_SOURCE_USER
  value: "{{ .Values.postgresql.auth.username }}"
- name: SW_DATA_SOURCE_PASSWORD
  value: "{{ .Values.postgresql.auth.password }}"
{{- else if eq .Values.oap.storageType "banyandb" }}
{{- $targets := .Values.banyandb.config.grpcAddress -}}
{{- if .Values.banyandb.enabled -}}
{{- $targets = printf "%s-grpc:%s" (include "skywalking.banyandb.fullname" .) (include "skywalking.banyandb.grpcPort" .) -}}
{{- end }}
- name: SW_STORAGE_BANYANDB_TARGETS
  value: "{{ $targets }}"
{{- if .Values.banyandb.auth.enabled }}
{{- if .Values.banyandb.auth.users }}
- name: SW_STORAGE_BANYANDB_USER
  value: "{{ (index .Values.banyandb.auth.users 0).username }}"
- name: SW_STORAGE_BANYANDB_PASSWORD
  value: "{{ (index .Values.banyandb.auth.users 0).password }}"
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Expand the name of the banyandb chart.
*/}}
{{- define "skywalking.banyandb.name" -}}
{{- default "skywalking-banyandb-helm" .Values.banyandb.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "skywalking.banyandb.fullname" -}}
{{- if .Values.banyandb.fullnameOverride -}}
{{- .Values.banyandb.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := (include "skywalking.banyandb.name" .) -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Define the banyandb http port
*/}}
{{- define "skywalking.banyandb.httpPort" -}}
{{- if .Values.banyandb.standalone.enabled -}}
{{- .Values.banyandb.standalone.httpSvc.port -}}
{{- else if .Values.banyandb.cluster.enabled -}}
{{- .Values.banyandb.cluster.liaison.httpSvc.port -}}
{{- end -}}
{{- end -}}

{{/*
Define the banyandb grpc port
*/}}
{{- define "skywalking.banyandb.grpcPort" -}}
{{- if .Values.banyandb.standalone.enabled -}}
{{- .Values.banyandb.standalone.grpcSvc.port -}}
{{- else if .Values.banyandb.cluster.enabled -}}
{{- .Values.banyandb.cluster.liaison.grpcSvc.port -}}
{{- end -}}
{{- end -}}

{{/*
Define volumeMounts for OAP containers
*/}}
{{- define "skywalking.oap.volumeMounts" -}}
{{- range $path, $config := .Values.oap.config }}
{{- if typeIs "string" $config }}
- name: skywalking-oap-override
  mountPath: /skywalking/config/{{ $path }}
  subPath: {{ $path }}
{{- else }}
{{- range $subpath, $subconfig := $config }}
{{- if typeIs "string" $subconfig }}
- name: skywalking-oap-override
  mountPath: /skywalking/config/{{ $path }}/{{ $subpath }}
  subPath: {{ print $path "-" $subpath }}
{{- else }}
{{- range $subsubpath, $subsubconfig := $subconfig }}
- name: skywalking-oap-override
  mountPath: /skywalking/config/{{ $path }}/{{ $subpath }}/{{ $subsubpath }}
  subPath: {{ print $path "-" $subpath "-" $subsubpath }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- range .Values.oap.secretMounts }}
- name: {{ .name }}
  mountPath: {{ .path }}
  {{- if .subPath }}
  subPath: {{ .subPath }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Define volumes for OAP containers
*/}}
{{- define "skywalking.oap.volumes" -}}
{{- if .Values.oap.config }}
- name: skywalking-oap-override
  configMap:
    name: {{ template "skywalking.fullname" . }}-oap-cm-override
{{- end }}
{{- range .Values.oap.secretMounts }}
- name: {{ .name }}
  secret:
    secretName: {{ .secretName }}
    {{- if .defaultMode }}
    defaultMode: {{ .defaultMode }}
    {{- end }}
{{- end }}
{{- end -}}
