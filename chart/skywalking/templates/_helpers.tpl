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
{{ default (include "skywalking.oap.fullname" .) .Values.serviceAccounts.oap }}
{{- end -}}

{{/*
Create the name of the service account to use for the satellite cluster
*/}}
{{- define "skywalking.serviceAccountName.satellite" -}}
{{ default (include "skywalking.satellite.fullname" .) .Values.serviceAccounts.satellite }}
{{- end -}}

{{- define "skywalking.containers.wait-for-es" -}}
- name: wait-for-elasticsearch
  image: {{ .Values.initContainer.image }}:{{ .Values.initContainer.tag }}
  imagePullPolicy: IfNotPresent
{{- if .Values.elasticsearch.enabled }}
  command: ['sh', '-c', 'for i in $(seq 1 60); do nc -z -w3 {{ .Values.elasticsearch.clusterName }}-{{ .Values.elasticsearch.nodeGroup }} {{ .Values.elasticsearch.httpPort }} && exit 0 || sleep 5; done; exit 1']
{{- else }}
  command: ['sh', '-c', 'for i in $(seq 1 60); do nc -z -w3 {{ .Values.elasticsearch.config.host }} {{ .Values.elasticsearch.config.port.http }} && exit 0 || sleep 5; done; exit 1']
{{- end }}
{{- end -}}
