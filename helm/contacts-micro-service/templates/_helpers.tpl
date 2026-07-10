{{- define "contacts-micro-service.name" -}}
contacts-micro-service
{{- end -}}

{{- define "contacts-micro-service.labels" -}}
app.kubernetes.io/name: {{ include "contacts-micro-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "contacts-micro-service.secretName" -}}
{{- if .Values.db.existingSecret -}}
{{ .Values.db.existingSecret }}
{{- else -}}
{{ include "contacts-micro-service.name" . }}-db
{{- end -}}
{{- end -}}
