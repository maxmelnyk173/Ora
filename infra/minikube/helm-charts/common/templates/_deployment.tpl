{{/*
Deployment template
*/}}
{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "common.labels" . | nindent 8 }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "common.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.initContainers }}
      initContainers:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          {{- with .Values.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          env:
            {{- include "common.defaultEnvVars" . | nindent 12 }}
            {{- with .Values.envVars }}
            {{- range . }}
            - name: {{ .name }}
            {{- if .value }}
              value: {{ .value | quote }}
            {{- else if .valueFrom }}
              valueFrom:
{{- toYaml .valueFrom | nindent 16 }}
            {{- end }}
            {{- end }}
            {{- end }}
      {{- with .Values.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}

{{/*
Default environment variables for platform services
*/}}
{{- define "common.defaultEnvVars" -}}
- name: POSTGRES_HOST
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: database.postgres.host
- name: POSTGRES_PORT
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: database.postgres.port
- name: KEYCLOAK_HOST
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.host
- name: KEYCLOAK_PORT
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.port
- name: KEYCLOAK_URL
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.url
- name: KEYCLOAK_REALM
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.realm
- name: KEYCLOAK_ADMIN_USER
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.user
- name: KEYCLOAK_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: keycloak-auth
      key: admin-password
- name: KEYCLOAK_ADMIN_CLIENT_ID
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.adminClientId
- name: KEYCLOAK_AUDIENCE
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.audience
- name: KEYCLOAK_AUTH_CLIENT
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.authClientId
- name: KEYCLOAK_JWKS_URI
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.jwksUri
- name: KEYCLOAK_ISSUER_URI
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: auth.keycloak.issuerUri
- name: RABBITMQ_HOST
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.host
- name: RABBITMQ_VHOST
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.vhost
- name: RABBITMQ_PORT
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.port
- name: RABBITMQ_USER
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.user
- name: RABBITMQ_PASS
  valueFrom:
    secretKeyRef:
      name: rabbitmq-auth
      key: admin-password
- name: RABBITMQ_EXCHANGE
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.exchange
- name: RABBITMQ_DLQ_EXCHANGE
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.dlqExchange
- name: RABBITMQ_MESSAGE_TTL
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: messaging.rabbitmq.messageTTL
- name: OTEL_GRPC_URL
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: observability.otelCollector.grpcEndpoint
- name: OTEL_HTTP_URL
  valueFrom:
    configMapKeyRef:
      name: platform-config
      key: observability.otelCollector.httpEndpoint
- name: ALLOWED_ORIGINS
  value: "*"
- name: ALLOWED_METHODS
  value: "GET,POST,PUT,DELETE,OPTIONS,PATCH"
- name: ALLOWED_HEADERS
  value: "Accept,Authorization,Content-Type,X-CSRF-Token"
- name: ALLOWED_CREDENTIALS
  value: "true"
{{- end }}