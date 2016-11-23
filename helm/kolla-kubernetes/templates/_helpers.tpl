{{- define "common_volume_mounts" }}
- mountPath: /var/log/kolla/
  name: kolla-logs
- mountPath: /etc/localtime
  name: host-etc-localtime
  readOnly: true
{{- if and .netHostTrue .Values.global.enableResolveConfNetHostWorkaround }}
- mountPath: /etc/resolv.conf
  name: resolv-conf
  subPath: resolv.conf
{{- end }}
{{- end }}

{{- define "common_containers" }}
{{- if .Values.global.enableKubeLogger }}
- name: logging
  image: "{{ .Values.global.fluentdImageFull }}"
  volumeMounts:
    - mountPath: {{ .Values.container_config_directory }}
      name: logging-config
{{- include "common_volume_mounts" . | indent 4 }}
  env:
    - name: KOLLA_CONFIG_STRATEGY
      value: COPY_ONCE
{{- end }}
{{- end }}

{{- define "common_volumes" }}
- name: host-etc-localtime
  hostPath:
    path: /etc/localtime
- name: kolla-logs
  emptyDir: {}
{{- $podTypeNotBootstrap := not .podTypeBootstrap }}
{{- if and .Values.global.enableKubeLogger $podTypeNotBootstrap }}
- name: logging-config
  configMap:
{{- $loggerConfigmapNameDefault := printf "%s-logging" .resourceName }}
    name: {{ .Values.logger_configmap_name | default $loggerConfigmapNameDefault }}
{{- end }}
{{- if and .netHostTrue .Values.global.enableResolveConfNetHostWorkaround }}
- name: resolv-conf
  configMap:
    name: resolv-conf
{{- end }}
{{- end }}
