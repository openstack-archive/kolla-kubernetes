#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_iscsi_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function entrypoint_config {
    general_config
    common_iscsi_config
}

tunnel_interface=docker0
base_distro="$2"

helm install kolla/compute-kit-0.5.0 --debug --version $VERSION \
    --namespace kolla --name compute-kit-0.5.0 \
    --values <(entrypoint_config)

$DIR/tools/wait_for_pods.sh kolla 900

$DIR/tools/build_local_admin_keystonerc.sh

kubectl get svc -n kolla
kubectl get pods -n kolla
netstat -tunlp
