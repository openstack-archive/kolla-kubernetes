#!/bin/bash -xe

[ "x$4" == "xiscsi" ] && echo "iscsi support pending..." && exit 0

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR

echo Setting up the gate...
env
echo Setting up the gate...

mkdir -p $WORKSPACE/logs/

sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh

virtualenv .venv
. .venv/bin/activate

git clone https://github.com/openstack/kolla.git
sudo ln -s `pwd`/kolla/etc/kolla /etc/kolla
sudo ln -s `pwd`/kolla /usr/share/kolla
sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes

cat tests/conf/ceph-all-in-one/kolla_config >> kolla/etc/kolla/globals.yml
IP=172.18.0.1
sed -i "s/^\(kolla_external_vip_address:\).*/\1 '$IP'/" \
    kolla/etc/kolla/globals.yml
sed -i "s/^\(kolla_kubernetes_external_vip:\).*/\1 '$IP'/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

echo "kolla_base_distro: $2" >> kolla/etc/kolla/globals.yml

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq
else
    sudo apt-get update
    sudo apt-get install -y crudini jq
fi

pushd kolla;
pip install pip --upgrade
pip install "ansible<2.1"
pip install "python-openstackclient"
pip install "python-neutronclient"
pip install -r requirements.txt
pip install pyyaml
./tools/generate_passwords.py
./tools/kolla-ansible genconfig
popd
pip install -r requirements.txt
pip install .

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

tests/bin/setup_gate_loopback.sh

tools/setup_kubernetes.sh

kubectl taint nodes --all dedicated-

NODE=$(hostname -s)

cat tests/conf/ceph-all-in-one/kolla_kubernetes_config \
    >> etc/kolla-kubernetes/kolla-kubernetes.yml

sed -i "s/initial_mon:.*/initial_mon: $NODE/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

kubectl label node $NODE kolla_controller=true
kubectl label node $NODE kolla_compute=true

#kubectl create -f https://git.io/weave-kube
url="https://raw.githubusercontent.com/tigera/canal/master"
url="$url/k8s-install/kubeadm/canal.yaml"

curl "$url" -o /tmp/canal.yaml

sed -i "s@192.168.0.0/16@172.16.130.0/23@" /tmp/canal.yaml
sed -i "s@100.78.232.136@172.16.128.100@" /tmp/canal.yaml

kubectl create -f /tmp/canal.yaml

kubectl describe node $NODE

tools/wait_for_pods.sh kube-system

kubectl create namespace kolla
tools/secret-generator.py create

TOOLBOX=$(kollakube tmpl bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')
sudo docker pull $TOOLBOX > /dev/null
timeout 240s tools/setup-resolv-conf.sh

kubectl get configmap resolv-conf --namespace=kolla -o yaml
kubectl get pods --all-namespaces -o wide

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume keepalived;

tests/bin/build_test_ceph.sh

kollakube res create pod ceph-admin ceph-rbd

tools/wait_for_pods.sh kolla

echo rbd script:
cat /usr/bin/rbd

str="ceph -w"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph.log &

for x in kollavolumes images volumes vms; do
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool create $x 64; ceph osd pool set $x size 1; ceph osd pool set $x min_size 1"
done
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool delete rbd rbd --yes-i-really-really-mean-it"
str="ceph auth get-or-create client.glance mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=images'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-glance-keyring --namespace=kolla\
    --from-file=ceph.client.glance.keyring=/tmp/$$
str="ceph auth get-or-create client.cinder mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-cinder-keyring --namespace=kolla\
    --from-file=ceph.client.cinder.keyring=/tmp/$$
str="ceph auth get-or-create client.nova mon 'allow r' osd 'allow "
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes, "
str="$str allow rwx pool=vms, allow rwx pool=images'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-nova-keyring --namespace=kolla \
    --from-file=ceph.client.nova.keyring=/tmp/$$
kubectl create secret generic nova-libvirt-bin --namespace=kolla \
    --from-file=data=<(awk '{if($1 == "key"){print $3}}' /tmp/$$ |
    tr -d '\n')
str="ceph auth get-or-create client.kolla mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=kollavolumes'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" | awk '{if($1 == "key"){print $3}}' > /tmp/$$
kubectl create secret generic ceph-kolla --namespace=kolla \
    --from-file=key=/tmp/$$
#FIXME may need different flags for testing jewel
str="cat /etc/ceph/ceph.conf"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"

str="timeout 240s rbd create kollavolumes/mariadb --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="timeout 60s rbd create kollavolumes/rabbitmq --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"

for volume in mariadb rabbitmq; do
    str='DEV=$(rbd map --pool kollavolumes '$volume'); mkfs.xfs $DEV;'
    str="$str rbd unmap "'$DEV;'
    timeout 60s kubectl exec ceph-admin -c main --namespace=kolla -- \
        /bin/bash -c "$str"
done

rm -f /tmp/$$
kollakube res create secret nova-libvirt

for x in mariadb rabbitmq; do
    kollakube res create pv $x
    kollakube res create pvc $x
done

kollakube res create svc mariadb memcached keystone-admin keystone-public \
    rabbitmq rabbitmq-management nova-api glance-api glance-registry \
    neutron-server nova-metadata nova-novncproxy horizon cinder-api

kollakube res create bootstrap mariadb-bootstrap rabbitmq-bootstrap

tools/pull_containers.sh kolla
tools/wait_for_pods.sh kolla

kollakube res delete bootstrap mariadb-bootstrap rabbitmq-bootstrap
kollakube res create pod mariadb memcached rabbitmq

tools/wait_for_pods.sh kolla

kollakube resource create bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

tools/pull_containers.sh kolla
tools/wait_for_pods.sh kolla

kollakube resource delete bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

kollakube res create pod keystone

tools/wait_for_pods.sh kolla

kollakube res create bootstrap nova-create-keystone-user \
    glance-create-keystone-user cinder-create-keystone-user \
    neutron-create-keystone-user \
    nova-create-keystone-endpoint-public \
    glance-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-publicv2 \
    neutron-create-keystone-endpoint-public

tools/wait_for_pods.sh kolla

kollakube res delete bootstrap nova-create-keystone-user \
    glance-create-keystone-user cinder-create-keystone-user \
    neutron-create-keystone-user \
    nova-create-keystone-endpoint-public \
    glance-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-publicv2 \
    neutron-create-keystone-endpoint-public

kollakube res create bootstrap glance-create-db glance-manage-db \
    nova-create-api-db nova-create-db neutron-create-db neutron-manage-db \
    cinder-create-db cinder-manage-db \
    nova-create-keystone-endpoint-internal \
    glance-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internalv2 \
    neutron-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \
    glance-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-adminv2 \
    neutron-create-keystone-endpoint-admin

tools/pull_containers.sh kolla
tools/wait_for_pods.sh kolla

mkdir -p $WORKSPACE/logs/
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla

tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

function endpoints_dump_and_fail {
    cat /tmp/$$.1
    openstack catalog list
    exit -1
}

OS_TOKEN=$(openstack token issue -f value -c id)
curl -H "X-Auth-Token:$OS_TOKEN" $OS_AUTH_URL/endpoints -o /tmp/$$
jq -r '.endpoints[] | .service_id' /tmp/$$ | sort | uniq -c > /tmp/$$.1
awk '{if($1 != 3){exit -1}}' /tmp/$$.1 || endpoints_dump_and_fail

kollakube res delete bootstrap glance-create-db glance-manage-db \
    nova-create-api-db nova-create-db neutron-create-db neutron-manage-db \
    cinder-create-db cinder-manage-db \
    nova-create-keystone-endpoint-internal \
    glance-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internalv2 \
    neutron-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \
    glance-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-adminv2 \
    neutron-create-keystone-endpoint-admin

kollakube res create pod nova-api nova-conductor nova-scheduler glance-api \
    glance-registry neutron-server horizon nova-consoleauth nova-novncproxy \
    cinder-api cinder-scheduler cinder-volume-ceph openvswitch-ovsdb-network \
    openvswitch-vswitchd-network

tools/pull_containers.sh kolla
tools/wait_for_pods.sh kolla

kollakube res create pod neutron-dhcp-agent neutron-l3-agent-network \
    neutron-openvswitch-agent-network neutron-metadata-agent-network

kollakube res create bootstrap openvswitch-set-external-ip
kollakube res create pod nova-libvirt
kollakube res create pod nova-compute
#kollakube res create pod keepalived

tools/pull_containers.sh kolla
tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

tools/wait_for_pods.sh kolla

kubectl get pods --namespace=kolla

tests/bin/basic_tests.sh
