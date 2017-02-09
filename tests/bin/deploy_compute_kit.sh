#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_iscsi_config.sh"

tunnel_interface=docker0
base_distro="$2"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function iscsi_config {
    common_iscsi_config
}

common_vars="ceph_backend=false,kube_logger=false,base_distro=$base_distro,global.kolla.keystone.all.admin_port_external=true"

general_config > /tmp/general_config.yaml
iscsi_config > /tmp/iscsi_config.yaml

helm install kolla/compute-kit-0.5.0 --version $VERSION \
    --namespace kolla --name compute-kit-0.5.0 \
    --values /tmp/general_config.yaml --values /tmp/iscsi_config.yaml

$DIR/tools/wait_for_pods.sh kolla 900

$DIR/tools/build_local_admin_keystonerc.sh
