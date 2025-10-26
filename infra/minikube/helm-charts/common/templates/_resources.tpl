{{/*
Render all common resources for a microservice
*/}}
{{- define "common.all" -}}
{{- if .Values.serviceAccount.create }}
{{ include "common.serviceAccount" . }}
---
{{- end }}
{{ include "common.service" . }}
---
{{ include "common.deployment" . }}
{{- if .Values.ingress.enabled }}
---
{{ include "common.ingress" . }}
{{- end }}
{{- if .Values.autoscaling.enabled }}
---
{{ include "common.hpa" . }}
{{- end }}
{{- end }}