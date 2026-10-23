{{/* Labels shared by every resource of this tenant. */}}
{{- define "footnote.labels" -}}
app.kubernetes.io/name: footnote
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: baseplate
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
