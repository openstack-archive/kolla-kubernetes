#!/bin/bash -xe

NODE=$(hostname -s)

TYPE="$2"
BRANCH="$3"

echo "kolla_base_distro: $1" >> /etc/kolla/globals.yml
cat tests/conf/ceph-all-in-one/kolla_config >> /etc/kolla/globals.yml
IP=172.18.0.1
sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    /etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    /etc/kolla-kubernetes/kolla-kubernetes.yml

cat tests/conf/ceph-all-in-one/kolla_kubernetes_config \
    >> /etc/kolla-kubernetes/kolla-kubernetes.yml

sed -i "s/initial_mon:.*/initial_mon: $NODE/" \
    /etc/kolla-kubernetes/kolla-kubernetes.yml

if [ "x$TYPE" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    echo "tunnel_interface: $interface" >> /etc/kolla/globals.yml
    echo "storage_interface: $interface" >> \
        /etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s/172.17.0.1/$(cat /etc/nodepool/primary_node_private)/" \
        /etc/kolla-kubernetes/kolla-kubernetes.yml
fi

if [ "x$BRANCH" == "x2" -o "x$BRANCH" == "x3" ]; then
    echo 'enable_placement: "no"' >> /etc/kolla/globals.yml
fi

# Generate passwords using SPRNG tool
tools/generate_passwords.py

# Build orch image
docker build . --tag="localhost:30400/kolla-kubernetes-orchestration:latest"
docker push localhost:30400/kolla-kubernetes-orchestration:latest

# Create secrets and configmaps
kubectl create secret generic --namespace=kolla --from-file /etc/kolla/passwords.yml passwords
kubectl create configmap --namespace=kolla --from-file /etc/kolla/globals.yml globals

# Generate configuration based upon defaults and overrides
ls -la /etc/kolla

mkdir /etc/kolla/overrides

crudini --set /etc/kolla/overrides/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/overrides/nova.conf libvirt cpu_mode none
UUID=$(awk '{if($1 == "cinder_rbd_secret_uuid:"){print $2}}' /etc/kolla/passwords.yml)
crudini --set /etc/kolla/overrides/nova.conf libvirt rbd_secret_uuid $UUID

# Keystone does not seem to invalidate its cache on entry point addition.
crudini --set /etc/kolla/overrides/keystone.conf cache enabled False

# sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/overrides/libvirtd.conf
# sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/overrides/libvirtd.conf

# sed -i \
#     '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\nosd crush chooseleaf type = 0\ndebug default = 5\n'\
#     /etc/kolla/overrides/ceph.conf

kubectl create configmap --namespace=kolla --from-file /etc/kolla/override conf-overrides
helm install helm/microservice/kolla-configs-job

# ./tools/fix-mitaka-config.py
