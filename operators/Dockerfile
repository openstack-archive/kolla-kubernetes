FROM centos:latest
# TODO(rhallisey): support kolla's build system
#FROM {{ namespace }}/{{ image_prefix }}base:{{ tag }}
#MAINTAINER {{ maintainer }}

COPY controller.py kubernetes_operator.py service_operator.py /opt/operator/bin/

CMD ["controller.py openstack"]
