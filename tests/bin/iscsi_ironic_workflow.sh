#!/bin/bash -xe
#
# Passed parameters $1 - Config, $2 - Distro, $3 - Branch
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
VERSION=0.6.0-1
IP=172.18.0.1
tunnel_interface=docker0
base_distro="$2"
branch="$3"
config="$1"

. "$DIR/tests/bin/deploy_iscsi_common.sh"
. "$DIR/tests/bin/deploy_ironic.sh"

function common_iscsi {
   deploy_iscsi_common  $IP $base_distro $tunnel_interface $branch $config
}

function ironic_base {
   deploy_ironic  $IP $base_distro $tunnel_interface $branch $config
}

function check_for_nova {
    for service in nova-scheduler nova-conductor nova-compute;
        do
           str=$(nova service-list | grep $service | awk '{print $12}')
           status=${str%%[[:space:]]*}
           if [ "x$status" != "xup" ]; then
              return 1
           fi
        done
    return 0
}

function wait_for_openstack {
    set +e
    count=0
    while true; do
        [ $count -gt 60 ] && echo Wait for openstack services failed... \
                           && return -1
        echo "Check for nova"
        check_for_nova
        retcode=$?
        if [ $retcode -eq 1 ]; then
           sleep 1
           count=$((count+1))
           continue
        else
           break
        fi
    done
    set -e
}
#
# Deploying common iscsi components
#
common_iscsi

#
# Deploying ironic
#
ironic_base

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin
wait_for_openstack

if [ "x$branch" != "x2" ]; then
helm install kolla/nova-cell0-create-db-job --debug --version $VERSION \
    --namespace kolla --name nova-cell0-create-db-job \
    --values /tmp/general_config.yaml --values /tmp/iscsi_config.yaml

$DIR/tools/wait_for_pods.sh kolla

helm install kolla/nova-api-create-simple-cell-job --debug --version $VERSION \
    --namespace kolla --name nova-api-create-simple-cell-job \
    --values /tmp/general_config.yaml --values /tmp/iscsi_config.yaml
fi

$DIR/tools/wait_for_pods.sh kolla

exit 0
