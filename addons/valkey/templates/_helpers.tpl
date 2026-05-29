{{/*
Expand the name of the chart.
*/}}
{{- define "valkey.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "valkey.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "valkey.labels" -}}
helm.sh/chart: {{ include "valkey.chart" . }}
{{ include "valkey.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "valkey.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "valkey.apiVersion" . }}
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
API version annotation
*/}}
{{- define "valkey.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Selector labels
*/}}
{{- define "valkey.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valkey.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define valkey cluster component definition regular expression name prefix
*/}}
{{- define "valkeyCluster.cmpdRegexpPattern" -}}
^valkey-cluster-\d+
{{- end -}}

{{/*
Define valkey cluster component script template name
*/}}
{{- define "valkeyCluster.scriptsTemplate" -}}
valkey-cluster-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{- define "metrics.repository" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository}}
{{- end }}

{{- define "metrics.image" -}}
{{ .Values.metrics.image.registry | default ( .Values.image.registry | default "docker.io" ) }}/{{ .Values.metrics.image.repository}}:{{ .Values.metrics.image.tag }}
{{- end }}

{{/*
Generate scripts configmap data block
*/}}
{{- define "valkey-cluster.extend.scripts" -}}
{{- range $path, $_ :=  $.Files.Glob "valkey-cluster-scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{- define "valkey.config.reconfigureAction" -}}
reconfigure:
  exec:
    container: valkey-cluster
    targetPodSelector: All
    command:
      - /bin/sh
      - -c
      - |
        set -eu

        env | cut -d= -f1 | grep -E '^[a-z0-9_.-][a-z0-9_.-]*$' | sort -u | while IFS= read -r param; do
          [ -n "${param}" ] || continue
          /scripts/reload-parameter.sh "${param}" "$(printenv "${param}")"
        done
{{- end -}}
