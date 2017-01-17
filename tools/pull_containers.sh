#!/bin/bash -e
set +x

sudo docker images | grep -v TAG | awk '{print $1,$2}' | while read -r image tag; do
    echo ${image}:${tag} >> /tmp/imags.$$
done

#Watch all images get pulled.
kubectl get pods --namespace $1 -o json | \
jq -r '.items[].spec.containers[].image' | sort -u | while read line; do
    grep "$line" /tmp/imags.$$ > /dev/null 2>&1 && continue || true
    echo Pulling container $line
    sudo docker pull $line > /dev/null
done
set -x
