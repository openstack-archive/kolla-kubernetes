#!/bin/bash -xe

VERSION=0.7.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

function wait_for_http {
    set +ex
    count=0
    while true; do
        curl -Lsf "$1" > /dev/null
        [ $? -eq 0 ] && break
        sleep 1
        count=$((count+1))
        [ $count -gt 30 ] && echo Failed to contact "$1". && exit -1
    done
    set -ex
}

helm install $DIR/helm/test/selenium --version $VERSION \
    --namespace kolla --name selenium

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

SELENIUM_IP=$(kubectl get svc hub --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}')
SELENIUM_URL=http://$SELENIUM_IP:4444/

HORIZON_URL=http://$(kubectl get svc horizon --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'):80/

wait_for_http $SELENIUM_URL
wait_for_http $HORIZON_URL

export HUB=$SELENIUM_IP
export OS_HORIZON=$HORIZON_URL
$DIR/tests/bin/horizon_test.py
