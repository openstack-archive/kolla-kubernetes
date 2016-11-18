FROM centos:latest
#FROM {{ namespace }}/{{ image_prefix }}base:{{ tag }}
#MAINTAINER {{ maintainer }}

COPY controller.py kubernetes_operator.py service_operator.py /

CMD ["controller.py openstack"]
