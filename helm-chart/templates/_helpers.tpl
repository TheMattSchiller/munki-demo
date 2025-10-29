{{/*
Expand the name of the chart.
*/}}
{{- define "munki-fileserver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "munki-fileserver.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "munki-fileserver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "munki-fileserver.labels" -}}
helm.sh/chart: {{ include "munki-fileserver.chart" . }}
{{ include "munki-fileserver.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "munki-fileserver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "munki-fileserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
SFTP selector labels
*/}}
{{- define "munki-fileserver.sftp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "munki-fileserver.name" . }}-sftp
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
NGINX selector labels
*/}}
{{- define "munki-fileserver.nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "munki-fileserver.name" . }}-nginx
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

