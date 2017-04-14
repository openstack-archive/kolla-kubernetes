#!/bin/bash -xe

NODE=$(hostname -s)

TYPE="$2"
BRANCH="$3"

echo "kolla_base_distro: $1" >> kolla-ansible/etc/kolla/globals.yml
cat tests/conf/ceph-all-in-one/kolla_config >> kolla-ansible/etc/kolla/globals.yml
IP=172.18.0.1
sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    kolla-ansible/etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

cat tests/conf/ceph-all-in-one/kolla_kubernetes_config \
    >> etc/kolla-kubernetes/kolla-kubernetes.yml

sed -i "s/initial_mon:.*/initial_mon: $NODE/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

if [ "x$TYPE" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    echo "tunnel_interface: $interface" >> kolla-ansible/etc/kolla/globals.yml
    echo "storage_interface: $interface" >> \
        etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s/172.17.0.1/$(cat /etc/nodepool/primary_node_private)/" \
        etc/kolla-kubernetes/kolla-kubernetes.yml
fi

if [ "x$BRANCH" == "x2" -o "x$BRANCH" == "x3" ]; then
    echo 'enable_placement: "no"' >> kolla-ansible/etc/kolla/globals.yml
fi

kolla-kubernetes/tools/generate_passwords.py
kolla-ansible/tools/kolla-ansible genconfig

# Testing ansible-in-k8s approach
rm -rf /etc/kolla/neutron*
rm -rf /etc/kolla/keystone*
rm -rf /etc/kolla/glance*
rm -rf /etc/kolla/horizon*
rm -rf /etc/kolla/nova*
rm -rf /etc/kolla/memcached*
rm -rf /etc/kolla/cinder*
rm -rf /etc/kolla/rabbitmq*
rm -rf /etc/kolla/heat*
rm -rf /etc/kolla/mariadb*
rm -rf /etc/kolla/ironic*

ansible-playbook -e ansible_python_interpreter=/usr/bin/python -e @/etc/kolla/globals.yml -e @/etc/kolla/passwords.yml -e CONFIG_DIR=/etc/kolla ansible/site.yml
ls -la /etc/kolla

crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_user nova
UUID=$(awk '{if($1 == "rbd_secret_uuid:"){print $2}}' /etc/kolla/passwords.yml)
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_secret_uuid $UUID

# Keystone does not seem to invalidate its cache on entry point addition.
crudini --set /etc/kolla/keystone/keystone.conf cache enabled False

sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf
sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/nova-libvirt/libvirtd.conf

sed -i \
    '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\nosd crush chooseleaf type = 0\ndebug default = 5\n'\
    /etc/kolla/ceph*/ceph.conf

./tools/fix-mitaka-config.py
