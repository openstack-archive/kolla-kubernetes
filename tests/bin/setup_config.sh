#!/bin/bash -xe

NODE=$(hostname -s)

TYPE="$2"

BRANCH="$6"

echo "kolla_base_distro: $1" >> kolla-ansible/etc/kolla/globals.yml
cat tests/conf/iscsi-all-in-one/kolla_config >> kolla-ansible/etc/kolla/globals.yml

# NOTE(sambetts) This needs to be the public IP of the Kubernetes master
IP={$IP:-172.18.0.1}

sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    kolla-ansible/etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml
# NOTE(sdake) this needs changing too
sed -i "s/^\(kolla_kubernetes_external_bridge_ip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

cat tests/conf/iscsi-all-in-one/kolla_kubernetes_config \
    >> etc/kolla-kubernetes/kolla-kubernetes.yml

sed -i "s/initial_mon:.*/initial_mon: $NODE/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

if [ "x$TYPE" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
else
    # NOTE(sambetts) some systems don't have NICs that are in this format!
    interface="enp10s0"
fi

if [ "x$TYPE" == "xceph-multi" -o "x$TYPE" == "xdev-env" ]; then
# NOTE(sdake) pass in any interface in some way
    echo "tunnel_interface: $interface" >> kolla-ansible/etc/kolla/globals.yml
    echo "storage_interface: $interface" >> \
        etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s/172.17.0.1/$IP/" \
        etc/kolla-kubernetes/kolla-kubernetes.yml
fi

if [ "x$TYPE" == "xdev-env" ]; then
    # NOTE(sambetts) Why? Can't I use my real hostname?
    sed -i "s/$(hostname -s)/oscorehost1/g" /etc/kolla-kubernetes/kolla-kubernetes.yml
fi

kolla-ansible/tools/generate_passwords.py
kolla-ansible/tools/kolla-ansible genconfig

crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_user nova
UUID=$(awk '{if($1 == "rbd_secret_uuid:"){print $2}}' /etc/kolla/passwords.yml)
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_secret_uuid $UUID

# Keystone does not seem to invalidate its cache on entry point addition.
crudini --set /etc/kolla/keystone/keystone.conf cache enabled False

sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf
sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/nova-libvirt/libvirtd.conf

cat > /etc/kollla/config/ceph.conf << __EOF__
osd pool default size = 1
osd pool default min size = 1
osd crush chooseleaf type = 0
debug default = 5
__EOF__

./tools/fix-mitaka-config.py
