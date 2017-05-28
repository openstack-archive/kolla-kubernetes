#!/bin/bash -xe

NODE=$(hostname -s)

DISTRO="$1"
CONFIG="$2"
BRANCH="$3"
TYPE="$4"

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

tools/generate_passwords.py
ansible-playbook -e ansible_python_interpreter=/usr/bin/python -e @/etc/kolla/globals.yml -e @/etc/kolla/passwords.yml -e CONFIG_DIR=/etc/kolla ansible/site.yml

crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none

# Keystone does not seem to invalidate its cache on entry point addition.
crudini --set /etc/kolla/keystone/keystone.conf cache enabled False

sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf
sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/nova-libvirt/libvirtd.conf

if [ "x$CONFIG" == "xironic" ]; then
   grep -r -l bridge_mappings /etc/kolla | xargs -l \
      sed  -i 's|\(bridge_mappings.*=.*\)|\1,physnet2:br-tenants|g'
fi
