#!/bin/bash -xe
# Set the below values if you are running behind a proxy
if [ -f "/etc/environment" ]; then
    RUN_ARGS="--env-file=/etc/environment"
else
    RUN_ARGS=""
fi

docker run -it --rm \
    --net=host \
    -v ~/.kube:/root/.kube:rw \
    $RUN_ARGS \
    kolla/k8s-devenv:latest
