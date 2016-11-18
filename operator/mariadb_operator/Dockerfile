FROM operator-base:latest
#FROM {{ namespace }}/{{ image_prefix }}base:{{ tag }}
#MAINTAINER {{ maintainer }}

RUN mkdir /mariadb_operator
COPY __init__.py mariadb_operator.py /mariadb_operator/

CMD ["controller.py mariadb"]