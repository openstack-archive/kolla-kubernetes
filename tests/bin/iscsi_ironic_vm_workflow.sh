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
  sudo yum install -y libvirt qemu-kvm ipmitool libvirt-devel
  sudo sed -i 's|log_level =.*|log_level = 1|g' /etc/libvirt/libvirtd.conf
  sudo sed -i 's|.log_outputs=.*|log_outputs="1:file:/var/log/libvirtd.log"|g' /etc/libvirt/libvirtd.conf
  sudo modprobe kvm
  sudo systemctl status libvirtd
  sudo systemctl start libvirtd
  sudo pip install libvirt-python
fi

git clone https://github.com/openstack/virtualbmc
cd virtualbmc/
sudo pip install -U .
#ipmitool -I lanplus -U admin -P password -H 127.0.0.1 power status
sudo virsh list --all
vbmc list
exit 0
