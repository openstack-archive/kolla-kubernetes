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

function ironic_base {
   deploy_ironic  $IP $base_distro $tunnel_interface $branch $config
}

#
# Deploying common iscsi components
#
common_iscsi

#
# Deploying ironic
#
ironic_base

. ~/keystonerc_admin
#
# Ironic and Virtual BMC
#
function wait_for_vbmc {
    set +x
    count=0
    while true; do
        val=$(sudo vbmc list | grep $1 | awk '{print $4}')
        [ $val == $2 ] && break
        [ $val == "error" ] && exit -1
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && exit -1
    done
    set -x
}
#
# Ironic related commands
#
pip install -U python-ironicclient
pip install -U python-ironic-inspector-client
kubectl get pods -n kolla | grep ironic
kubectl get svc -n kolla | grep ironic
kubectl get configmaps -n kolla | grep ironic
kubectl describe svc ironic-api -n kolla
kubectl describe svc ironic-inspector -n kolla
nova service-list

openstack baremetal node create \
          --driver pxe_ipmitool \
          --driver-info ipmi_username=admin \
          --driver-info ipmi_password=password \
          --driver-info ipmi_address=127.0.0.1
wait_for_ironic_node

if [ "x$base_distro" == "xubuntu" ]; then
  echo 'exit 101' | sudo tee /usr/sbin/policy-rc.d
  sudo chmod +x /usr/sbin/policy-rc.d
  sudo apt-get update
  sudo apt-get install -y libvirt-bin libvirt-dev \
                          qemu-kvm qemu-utils ipmitool \
                          pkg-config
  sudo sed -i 's|/usr/libexec/qemu-kvm|/usr/bin/qemu-system-x86_64|g' $DIR/tests/conf/ironic/vm-1.xml
else
  sudo yum install -y libvirt qemu-kvm qemu-img ipmitool libvirt-client libvirt-devel
fi
sudo modprobe kvm
#
# Load required images to glance
#
ironic_url="http://tarballs.openstack.org/ironic-python-agent/tinyipa/files"
curl -L $ironic_url/tinyipa-stable-newton.gz \
          -o ironic-agent.initramfs
curl -L $ironic_url/tinyipa-stable-newton.vmlinuz \
          -o ironic-agent.kernel
timeout 120s openstack image create --file ironic-agent.initramfs --disk-format ari \
     --container-format ari --public ironic-agent.initramfs
timeout 120s openstack image create --file ironic-agent.kernel --disk-format aki \
     --container-format aki --public ironic-agent.kernel
openstack image list
#
# Installing Virtual BMC software
#
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
#
sudo vbmc add vm-1
wait_for_vbmc vm-1 "down"
sudo vbmc start vm-1
wait_for_vbmc vm-1 "running"
#
# Check power status and status of vbmc
#
sudo ipmitool -I lanplus -U admin -P password -H 127.0.0.1 power status
sudo vbmc list
sudo vbmc show vm-1

openstack baremetal node list
node_id=$(openstack baremetal node list -c "UUID" -f value)
openstack baremetal node show $node_id
openstack baremetal introspection rule list
#
# Creating baremetal flavor for VM: RAM 512MB
# HD 5GB CPU 1
openstack flavor create --disk 5 --ram 512 --vcpus 1 baremetal 
openstack flavor set --property cpu_arch=x86_64 baremetal
#
# Updating ironic node info
#
DEPLOY_VMLINUZ_UUID=$(openstack image list | grep kernel | awk '{print $2}')
DEPLOY_INITRD_UUID=$(openstack image list | grep initramfs | awk '{print $2}' )
ironic node-update $node_id add \
    driver_info/deploy_kernel=$DEPLOY_VMLINUZ_UUID \
    driver_info/deploy_ramdisk=$DEPLOY_INITRD_UUID
openstack baremetal node show $node_id
ironic node-validate $node_id
sleep 2
ironic port-create -n $node_id -a 00:01:DE:AD:BE:EF
sleep 2
ironic port-list
sleep 2

exit 0
