#!/bin/bash -xe
# Set the below values if you are running behind a proxy
#RUN_ARGS="--env-file=/etc/environment"
RUN_ARGS=""
docker run -it --rm \
    --net=host \
    -v ~/.kube:/root/.kube:rw \
    $RUN_ARGS \
    kolla/k8s-devenv:latest
