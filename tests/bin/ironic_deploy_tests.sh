#!/bin/bash -xe
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

function wait_for_vm {
    set +x
    count=0
    while true; do
        val=$(openstack server show $1 -f value -c OS-EXT-STS:vm_state)
        [ $val == "active" ] && break
        [ $val == "error" ] && openstack server show $1 && exit -1
        sleep 1;
        count=$((count+1))
        [ $count -gt 120 ] && exit -1
    done
    set -x
}

function wait_for_baremetal_resources {
    set +x
    count=0
    while true; do
        hv_ram=$(openstack hypervisor stats show -f value -c memory_mb)
        hv_vcpus=$(openstack hypervisor stats show -f value -c vcpus)
        hv_disk=$(openstack hypervisor stats show -f value -c local_gb)
        [ $hv_ram -eq $1 -a $hv_disk -eq $2 -a $hv_vcpus -eq $3 ] && break
        sleep 1;
        count=$((count+1))
        [ $count -gt 180 ] && openstack hypervisor stats show && exit -1
    done
    set -x
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
base_distro="$2"
branch="$3"
config="$1"
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
  sudo sed -i 's|/usr/libexec/qemu-kvm|/usr/bin/qemu-system-x86_64|g' $DIR/../conf/ironic/vm-1.xml
else
  sudo yum install -y libvirt qemu-kvm-ev qemu-img-ev ipmitool libvirt-client libvirt-devel
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
CPU=1
RAM_MB=512
DISK_GB=1
ARCH="x86_64"
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vm-1.qcow2 $DISK_GB
pwd
sudo virsh define $DIR/../conf/ironic/vm-1.xml
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
# Creating baremetal flavor for VM
#
openstack flavor create --disk $DISK_GB --ram $RAM_MB --vcpus $CPU baremetal
openstack flavor set --property cpu_arch=$ARCH baremetal
#
# Taking a snapshot of hypervisor's current values for ram, local_gb and vcpus
#
hv_ram=$(openstack hypervisor stats show -f value -c memory_mb)
hv_vcpus=$(openstack hypervisor stats show -f value -c vcpus)
hv_disk=$(openstack hypervisor stats show -f value -c local_gb)
exp_ram=$((hv_ram + RAM_MB))
exp_vcpus=$((hv_vcpus + CPU))
exp_disk=$((hv_disk + DISK_GB))
#
# Updating ironic node info
#
DEPLOY_VMLINUZ_UUID=$(openstack image list | grep kernel | awk '{print $2}')
DEPLOY_INITRD_UUID=$(openstack image list | grep initramfs | awk '{print $2}')
ironic node-update $node_id add \
    driver_info/deploy_kernel=$DEPLOY_VMLINUZ_UUID \
    driver_info/deploy_ramdisk=$DEPLOY_INITRD_UUID
openstack baremetal node show $node_id
ironic node-validate $node_id
sleep 2
ironic node-update $node_id add \
    properties/cpus=$CPU \
    properties/memory_mb=$RAM_MB \
    properties/local_gb=$DISK_GB \
    properties/cpu_arch=$ARCH
sleep 2
ironic port-create -n $node_id -a 00:01:DE:AD:BE:EF
sleep 2
ironic port-list
sleep 2
#
# Adding neutron net/subnet and plug it to neutron router
#
sudo docker exec -tu root $(sudo docker ps | grep neutron-server: \
    | awk '{print $1}') cat /etc/neutron/plugins/ml2/ml2_conf.ini
sudo docker exec -tu root $(sudo docker ps | grep openvswitch-vswitchd: \
    | awk '{print $1}') ovs-vsctl show
openstack network create --share --provider-network-type flat \
    --provider-physical-network physnet2 baremetal
neutron subnet-create --gateway=172.21.0.1 \
    --allocation-pool start=172.21.0.100,end=172.21.0.200 \
    --name baremetal baremetal 172.21.0.0/24
openstack router add subnet $(openstack router list -f value -c ID) \
                            baremetal
#
# Configuring host aggregates
#
vm_compute=$(nova service-list | grep compute | grep -v ironic \
             | awk '{print $6}')
ironic_compute=$(nova service-list | grep compute | grep ironic \
                 | grep -v down | awk '{print $6}')
openstack aggregate create --property baremetal=true baremetal-hosts
sleep 2
openstack flavor set baremetal --property baremetal=true
sleep 2
openstack aggregate add host baremetal-hosts $ironic_compute
sleep 2
openstack aggregate set --property cpu_arch=$ARCH baremetal-hosts
sleep 2
openstack aggregate show baremetal-hosts

ironic node-validate $node_id

#
# Need to wait until nova is aware of resources provided by baremetal node
#
wait_for_baremetal_resources $exp_ram $exp_disk $exp_vcpus

#
# Checking nova db to see compute resource
#
user='root'
password=$(python -c 'import yaml; print yaml.safe_load(open("/etc/kolla/passwords.yml"))["database_password"]')
kubectl exec mariadb-0 -n kolla -- mysql --user=$user --password=$password -e 'use nova;select * from compute_nodes;'
kubectl exec mariadb-0 -n kolla -- mysql --user=$user --password=$password -e 'use ironic;select * from nodes;'


openstack server create \
          --image $(openstack image list | grep CirrOS | awk '{print $2}') \
          --flavor baremetal\
          --nic net-id=$(openstack network list | grep baremetal | awk '{print $2}') \
          baremetal-1

openstack server list
openstack server show baremetal-1
openstack port list
wait_for_vm baremetal-1

openstack baremetal node show $node_id
openstack server list
openstack port list
ironic node-validate $node_id
ironic port-list
ironic port-show $(ironic port-list | grep be:ef | awk '{print $2}' )
virsh list
virsh dumpxml vm-1

exit 0
