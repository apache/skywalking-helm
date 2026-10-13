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
Labels.

A release has one label style, fixed by how it was first installed:

- "modern", a release installed with 5.1.0 or later: only the Kubernetes recommended labels
  (app.kubernetes.io/*, helm.sh/chart), and every selector matches on them: the Deployments, the
  Services, OAP cluster discovery and dynamic configuration (SW_CLUSTER_K8S_LABEL), Satellite's OAP
  lookup and pod anti-affinity.
- "legacy", a release installed before 5.1.0: the Helm 2 labels it always had (app, release,
  component, chart, heritage) plus the recommended ones, and every selector keeps matching on the
  Helm 2 labels. A Deployment's selector is immutable, so such a release cannot switch in place.

"skywalking.labelStyle" decides which. The label helpers take (dict "context" $ "component" "<c>");
"legacyComponent" overrides the legacy component value where it differs (the OAP init Job).
*/}}

{{/*
The release's label style, "legacy" or "modern". `labelStyle: auto` looks the release's Deployments up
in the order OAP, UI, Satellite: the first that exists decides, legacy when its selector has the Helm 2
`release` key. A release with none of them is new, so modern. `lookup` returns nothing when the chart is
rendered without cluster access (`helm template`, Argo CD, `--dry-run=client`), so a release installed
before 5.1.0 that is rendered that way must set `labelStyle: legacy`.
*/}}
{{- define "skywalking.labelStyle" -}}
{{- $style := .Values.labelStyle | default "auto" -}}
{{- if not (has $style (list "auto" "legacy" "modern")) -}}
{{- fail (printf "labelStyle must be auto, legacy or modern, got %v" $style) -}}
{{- end -}}
{{- if eq $style "auto" -}}
{{- $style = "" -}}
{{- range $name := list (include "skywalking.oap.fullname" $) (include "skywalking.ui.fullname" $) (include "skywalking.satellite.fullname" $) -}}
{{- if not $style -}}
{{- $existing := lookup "apps/v1" "Deployment" $.Release.Namespace $name -}}
{{- if $existing -}}
{{- $style = ternary "legacy" "modern" (not (empty (dig "spec" "selector" "matchLabels" "release" "" $existing))) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $style | default "modern" -}}
{{- end -}}

{{/*
app.kubernetes.io/name: the chart name, as the Kubernetes recommended labels define it. The legacy
"app" label holds the release name instead, see "skywalking.name".

It ignores nameOverride on purpose. The label is part of the Deployment selector of a modern release,
and that selector is immutable, while nameOverride can change on an upgrade without renaming the
Deployments when fullnameOverride is set. nameOverride only names resources.
*/}}
{{- define "skywalking.appName" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "skywalking.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "skywalking.selectorLabels.legacy" -}}
app: {{ include "skywalking.name" .context | quote }}
release: {{ .context.Release.Name | quote }}
component: {{ default .component .legacyComponent | trunc 63 | trimSuffix "-" | quote }}
{{- end -}}

{{- define "skywalking.selectorLabels.modern" -}}
app.kubernetes.io/name: {{ include "skywalking.appName" .context | quote }}
app.kubernetes.io/instance: {{ .context.Release.Name | quote }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end -}}

{{/*
Selector labels in the release's style: Deployment selectors, Service selectors, pod anti-affinity.
*/}}
{{- define "skywalking.selectorLabels" -}}
{{- if eq (include "skywalking.labelStyle" .context) "legacy" -}}
{{ include "skywalking.selectorLabels.legacy" . }}
{{- else -}}
{{ include "skywalking.selectorLabels.modern" . }}
{{- end -}}
{{- end -}}

{{/*
Pod labels. A legacy release's pods carry both sets, so its selectors keep matching and a later move
to the modern style finds the recommended labels already in place. No chart version here, or every
chart upgrade would restart the pods.
*/}}
{{- define "skywalking.podLabels" -}}
{{- if eq (include "skywalking.labelStyle" .context) "legacy" -}}
{{ include "skywalking.selectorLabels.legacy" . }}
{{ include "skywalking.selectorLabels.modern" . }}
{{- else -}}
{{ include "skywalking.selectorLabels.modern" . }}
{{- end -}}
{{- end -}}

{{/*
Resource labels: the pod labels plus the chart and manager labels.
*/}}
{{- define "skywalking.labels" -}}
{{ include "skywalking.podLabels" . }}
app.kubernetes.io/managed-by: {{ .context.Release.Service | quote }}
helm.sh/chart: {{ include "skywalking.chart" .context | quote }}
{{- if eq (include "skywalking.labelStyle" .context) "legacy" }}
chart: {{ include "skywalking.chart" .context | quote }}
heritage: {{ .context.Release.Service | quote }}
{{- end }}
{{- end -}}

{{/*
The OAP pods' selector as a comma-separated string, in the release's style. OAP uses it to find its
peers and its dynamic-configuration ConfigMap (SW_CLUSTER_K8S_LABEL), and Satellite uses it to find
OAP (SATELLITE_GRPC_CLIENT_KUBERNETES_SELECTOR_LABEL).
*/}}
{{- define "skywalking.oap.labels" -}}
{{- if eq (include "skywalking.labelStyle" .) "legacy" -}}
app={{ template "skywalking.name" . }},release={{ .Release.Name }},component={{ .Values.oap.name }}
{{- else -}}
app.kubernetes.io/name={{ include "skywalking.appName" . }},app.kubernetes.io/instance={{ .Release.Name }},app.kubernetes.io/component={{ .Values.oap.name }}
{{- end -}}
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

{{/*
Expand the fullname of the ECK-managed Elasticsearch resource.
The ECK operator creates a service named {fullname}-es-http.
*/}}
{{- define "skywalking.elasticsearch.fullname" -}}
{{- if .Values.elasticsearch.fullnameOverride -}}
{{- .Values.elasticsearch.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-elasticsearch" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "skywalking.containers.wait-for-storage" -}}
{{- if eq .Values.oap.storageType "elasticsearch" }}
- name: wait-for-elasticsearch
  image: {{ .Values.initContainer.image }}:{{ .Values.initContainer.tag }}
  imagePullPolicy: IfNotPresent
    {{- if .Values.elasticsearch.enabled }}
  command: ['sh', '-c', 'for i in $(seq 1 60); do nc -z -w3 {{ include "skywalking.elasticsearch.fullname" . }}-es-http 9200 && exit 0 || sleep 5; done; exit 1']
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
  value: "{{ include "skywalking.elasticsearch.fullname" . }}-es-http:9200"
  {{- else }}
  value: "{{ .Values.elasticsearch.config.host }}:{{ .Values.elasticsearch.config.port.http }}"
  {{- end }}
  {{- if .Values.elasticsearch.enabled }}
- name: SW_ES_USER
  value: "elastic"
- name: SW_ES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "skywalking.elasticsearch.fullname" . }}-es-elastic-user
      key: elastic
  {{- else }}
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
