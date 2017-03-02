#!/bin/bash -xe
#
# Passed parameters $1 - Config, $2 - Distro, $3 - Branch
#

function wait_for_ironic_node {
    set +x
    count=0
    while true; do
        val=$(openstack baremetal node list -c "Provisioning State" -f value)
        node_id=$(openstack baremetal node list -c "UUID" -f value)
        [ $val == "available" ] && break
        [ $val == "error" ] && openstack baremetal node show $node_id && exit -1
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && openstack baremetal node show $node_id && exit -1
    done
    set -x
}

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

function ironic {
   deploy_ironic  $IP $base_distro $tunnel_interface $branch $config
}

#
# Deploying common iscsi components
#
common_iscsi

#
# Deploying ironic
#
ironic

. ~/keystonerc_admin

#
# Ironic related commands
#
pip install -U python-ironicclient
pip install -U python-ironic-inspector-client
kubectl get pods -n kolla | grep ironic
kubectl get svc -n kolla | grep ironic
kubectl get configmaps -n kolla | grep ironic
kubectl describe svc ironic-api -n kolla
nova service-list

openstack baremetal node create --driver pxe_ipmitool

wait_for_ironic_node

openstack baremetal node list
node_id=$(openstack baremetal node list -c "UUID" -f value)
openstack baremetal node show $node_id

openstack baremetal introspection rule list
