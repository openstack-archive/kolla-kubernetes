#!/bin/bash -xe
mkdir $WORKSPACE/logs/prometheus/
kubectl get pods -n kolla -o json | \
    jq -r '.items[].metadata | select(.annotations."prometheus.io/scrape") | .name' | \
    while read pod; do
        port=$(kubectl get pods $pod -n kolla -o json | \
               jq -r '.metadata.annotations."prometheus.io/port"')
        path=$(kubectl get pods $pod -n kolla -o json | \
               jq -r '.metadata.annotations."prometheus.io/path"')
        ip=$(kubectl get pods $pod -n kolla -o json | \
               jq -r '.status.podIP')
        if [ "x$port" == x -o "x$port" == "xnull" ]; then
            port="9100"
        fi
        if [ "x$path" == x -o "x$path" == "xnull" ]; then
            path="/metrics"
        fi
        curl -s http://$ip:$port$path > $WORKSPACE/logs/prometheus/$pod.pom
    done

