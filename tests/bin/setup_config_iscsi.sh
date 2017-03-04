#!/bin/bash -xe

NODE=$(hostname -s)

DISTRO="$1"
TYPE="$2"
BRANCH="$3"

echo "kolla_base_distro: $1" >> kolla-ansible/etc/kolla/globals.yml
cat tests/conf/iscsi-all-in-one/kolla_config >> kolla-ansible/etc/kolla/globals.yml
IP=172.18.0.1
sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    kolla-ansible/etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

# NOTE(sbezverk) After ceph, set-ip and keepalived get converted
# to helm charts, the following three lines can be removed.
if [ "x$TYPE" == "xsource" ]; then
   sed -i 's/.*kolla_install_type:.*/kolla_install_type: \"source\"/g' /etc/kolla/globals.yml
fi

cat tests/conf/iscsi-all-in-one/kolla_kubernetes_config \
    >> etc/kolla-kubernetes/kolla-kubernetes.yml

#
# Ironic needs 2 files pulled from OpenStack
#
#ironic_url="http://tarballs.openstack.org/ironic-python-agent/tinyipa/files"
#sudo mkdir -p /etc/kolla/config/ironic/
#sudo curl -L $ironic_url/tinyipa-stable-newton.gz \
#          -o /etc/kolla/config/ironic/ironic-agent.initramfs
#sudo curl -L $ironic_url/tinyipa-stable-newton.vmlinuz \
#          -o /etc/kolla/config/ironic/ironic-agent.kernel

kolla-ansible/tools/generate_passwords.py
kolla-ansible/tools/kolla-ansible genconfig

crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none

# Keystone does not seem to invalidate its cache on entry point addition.
crudini --set /etc/kolla/keystone/keystone.conf cache enabled False

sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf
sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/nova-libvirt/libvirtd.conf
