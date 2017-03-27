#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/kubeadm/canal.yaml"

curl "$url" -o /tmp/canal.yaml

sed -i "s@192.168.0.0/16@172.16.130.0/22@" /tmp/canal.yaml
sed -i "s@10.96.232.136@172.16.128.100@" /tmp/canal.yaml

kubectl create -f /tmp/canal.yaml

$DIR/tools/pull_containers.sh kube-system
$DIR/tools/wait_for_pods.sh kube-system

$DIR/tools/test_kube_dns.sh
