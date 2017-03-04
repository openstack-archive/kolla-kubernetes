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

DISTRO=$2
CONFIG=$1
if [ "x$DISTRO" == "xubuntu" ]; then
exit 0
else
  sudo yum install -y libvirt qemu-kvm qemu-img ipmitool libvirt-client libvirt-devel
  sudo modprobe kvm
fi

sudo pip install libvirt-python
git clone https://github.com/openstack/virtualbmc
cd virtualbmc
sudo pip install -U .
#
# Prepare VM
#
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vm-1.qcow2 5G
sudo virsh define $DIR/tests/conf/ironic/vm-1.xml
sudo virsh list --all
#
# Add virtual bmc to VM
# (sleep is temporary)
vbmc add vm-1
sleep 10
vbmc start vm-1
sleep 10
#
# Check power status and status of vbmc
#
ipmitool -I lanplus -U admin -P password -H 127.0.0.1 power status
vbmc list
vbmc show $(vbmc list | grep cirros-1 | awk '{print $2}')
exit 0
