#!/bin/bash -xe

echo "kolla_base_distro: $1" >> kolla/etc/kolla/globals.yml
cat tests/conf/ceph-all-in-one/kolla_config >> kolla/etc/kolla/globals.yml
IP=172.18.0.1
sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    kolla/etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

kolla/tools/generate_passwords.py
kolla/tools/kolla-ansible genconfig

crudini --set /etc/kolla/nova-compute/nova.conf cinder catalog_info volumev2:cinderv2:internalURL
crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_user nova
UUID=$(awk '{if($1 == "rbd_secret_uuid:"){print $2}}' /etc/kolla/passwords.yml)
crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_secret_uuid $UUID

sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf

sed -i \
    '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\nosd crush chooseleaf type = 0\ndebug default = 5\n'\
    /etc/kolla/ceph*/ceph.conf

./tools/fix-mitaka-config.py
