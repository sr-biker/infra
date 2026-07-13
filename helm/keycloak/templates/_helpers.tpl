{{- define "keycloak.name" -}}
keycloak
{{- end -}}

{{- define "keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "keycloak.labels" -}}
{{ include "keycloak.selectorLabels" . }}
environment: {{ .Values.environment }}
{{- end -}}
