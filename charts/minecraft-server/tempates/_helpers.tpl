{{- define "mc.name" -}}
minecraft-server
{{- end }}

{{- define "mc.fullname" -}}
{{ .Release.Name }}-minecraft
{{- end }}
