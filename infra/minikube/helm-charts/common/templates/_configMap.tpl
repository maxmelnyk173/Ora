{{/*
ConfigMap template
*/}}
{{- define "common.configMap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
    name: {{ include "common.fullname" . }}-config
    labels:
        {{- include "common.labels" . | nindent 4 }}
data:
    {{- range $key, $value := .Values.configMap.data }}
    {{ $key }}: |-
        {{ $value | nindent 4 }}
    {{- end }}
{{- end }}