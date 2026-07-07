# Claude API configuration — only emit when ANTHROPIC_API_KEY is
# actually set, so an empty assignment does not override direnv or
# other project-level config that a user may have in .envrc.
{{- if .env.ANTHROPIC_API_KEY }}
export ANTHROPIC_API_KEY="{{ .env.ANTHROPIC_API_KEY }}"
{{- end }}