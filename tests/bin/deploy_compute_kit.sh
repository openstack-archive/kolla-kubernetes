#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_iscsi_config.sh"

VERSION=0.6.0-1
IP=172.18.0.1
tunnel_interface=docker0
base_distro="$2"

function check_for_nova {
    for service in nova-scheduler nova-conductor nova-compute;
        do
           status=$(nova service-list | grep $service | awk '{print $12}')
           if [ "x$status" != "xup" ]; then
              return 1
           fi
        done
    return 0
}

function check_for_neutron {
    for service in neutron-l3-agent neutron-metadata-agent neutron-dhcp-agent \
                   neutron-openvswitch-agent;
        do
           agent_id=$(neutron agent-list | grep $service | awk '{print $2}')
           status=$(neutron agent-show $agent_id -f value -c alive)
           if [ "x$status" != "xTrue" ]; then
              return 1
           fi
        done
    return 0
}

function check_for_cinder {
    for service in cinder-scheduler cinder-volume;
        do
           status=$(cinder service-list | grep $service | awk '{print $10}')
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
        [ $count -gt 600 ] && echo Wait for openstack services failed... \
                           && return -1
        echo "Check for nova"
        check_for_nova
        retcode=$?
        if [ $retcode -eq 1 ]; then
           sleep 1
           count=$((count+1))
           continue
        fi
        echo "check for neutron"
        check_for_neutron
        retcode=$?
        if [ $retcode -eq 1 ]; then
           sleep 1
           count=$((count+1))
           continue
        fi
        echo "check for cinder"
        check_for_cinder
        retcode=$?
        if [ $retcode -eq 1 ]; then
           sleep 1
           count=$((count+1))
           continue
        fi
        break
    done
    set -e
}

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function iscsi_config {
    common_iscsi_config
}

general_config > /tmp/general_config.yaml
iscsi_config > /tmp/iscsi_config.yaml

NOVA_PLACEMENT_ENABLE=true
if [ "x$branch" == "x2" -o "x$branch" == "x3" ]; then
  NOVA_PLACEMENT_ENABLE=false
fi

helm install kolla/compute-kit --version $VERSION \
    --namespace kolla --name compute-kit \
    --values /tmp/general_config.yaml --values /tmp/iscsi_config.yaml \
    --set global.kolla.nova.all.placement_enabled=$NOVA_PLACEMENT_ENABLE


$DIR/tools/wait_for_pods.sh kolla 900

kollakube res create bootstrap openvswitch-set-external-ip
$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

wait_for_openstack
