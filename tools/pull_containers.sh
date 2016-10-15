#!/bin/bash -e
set +x
#Watch all images get pulled.
kubectl get pods --namespace $1 -o json | \
jq -r '.items[].spec.containers[].image' | sort -u | while read line; do
    echo Pulling container $line
    sudo docker pull $line > /dev/null
done
set -x
