FROM operator-base:latest
# TODO(rhallisey): support kolla's build system
#FROM {{ namespace }}/{{ image_prefix }}base:{{ tag }}
#MAINTAINER {{ maintainer }}

RUN mkdir /mariadb_operator
COPY __init__.py mariadb_operator.py /opt/operator/bin

CMD ["controller.py mariadb"]