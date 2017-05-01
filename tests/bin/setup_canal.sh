#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/canal.yaml"

curl "$url" -o /tmp/canal.yaml

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/rbac.yaml"

curl "$url" -o /tmp/rbac.yaml

kubectl create -f /tmp/rbac.yaml

kubectl create -f /tmp/canal.yaml

$DIR/tools/pull_containers.sh kube-system
$DIR/tools/wait_for_pods.sh kube-system 240
