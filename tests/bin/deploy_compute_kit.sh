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
           status=$(neutron agent-list | grep $service | awk '{print $12}')
           if [ "x$status" != "x:-)" ]; then
              return 1
           fi
        done
    return 0
}

function check_for_cindrer {
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
    set +ex
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
    done
    set -ex
}

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function iscsi_config {
    common_iscsi_config
}

general_config > /tmp/general_config.yaml
iscsi_config > /tmp/iscsi_config.yaml

helm install kolla/compute-kit --version $VERSION \
    --namespace kolla --name compute-kit \
    --values /tmp/general_config.yaml --values /tmp/iscsi_config.yaml

$DIR/tools/wait_for_pods.sh kolla 900

kollakube res create bootstrap openvswitch-set-external-ip
$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

# It looks like after containers are up OpenStack services needs extra time to
# come up, giving extra 10 minutes to settle.
$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin
pip list
nova service-list
neutron agent-list
cinder service-list

sleep 600

nova service-list
neutron agent-list
agent_id=$(neutron agent-list | grep neutron-l3-agent | awk '{print $2}')
neutron agent-show $agent_id
cinder service-list
