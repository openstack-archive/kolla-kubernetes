#!/bin/bash -xe

function pull_containers {
    set +x
    #Watch all images get pulled.
    kubectl get pods --namespace $1 -o json | \
    jq -r '.items[].spec.containers[].image' | sort -u | while read line; do
        echo Pulling container $line
        sudo docker pull $line > /dev/null
    done
    set -x
}

function wait_for_pods {
    set +x
    end=$(date +%s)
    end=$((end + 120))
    while true; do
        kubectl get pods --namespace=$1 -o json | jq -r \
            '.items[].status.phase' | grep Pending > /dev/null && \
            PENDING=True || PENDING=False
        query='.items[]|select(.status.phase=="Running")'
        query="$query|.status.containerStatuses[].ready"
        kubectl get pods --namespace=$1 -o json | jq -r "$query" | \
            grep false > /dev/null && READY="False" || READY="True"
        kubectl get jobs -o json --namespace=$1 | jq -r \
            '.items[] | .spec.completions == .status.succeeded' | \
            grep false > /dev/null && JOBR="False" || JOBR="True"
        [ $PENDING == "False" -a $READY == "True" -a $JOBR == "True" ] && \
            break || true
        sleep 1
        now=$(date +%s)
        [ $now -gt $end ] && echo containers failed to start. && \
            kubectl get pods --namespace $1 && exit -1
    done
    set -x
}

function wait_for_ceph_bootstrap {
    set +x
    end=$(date +%s)
    end=$((end + 120))
    while true; do
        kubectl get pods --namespace=$1 | grep ceph-bootstrap-osd && \
            PENDING=True || PENDING=False
        [ $PENDING == "False" ] && break
        sleep 1
        now=$(date +%s)
        [ $now -gt $end ] && echo containers failed to start. && \
            kubectl get pods --namespace $1 && exit -1
    done
}

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

wait_for_pods kube-system

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
    cinder-scheduler cinder-volume ceph-mon ceph-osd keepalived;

kollakube res create bootstrap ceph-bootstrap-initial-mon

pull_containers kolla
wait_for_pods kolla

tools/setup-ceph-secrets.sh
kollakube res delete bootstrap ceph-bootstrap-initial-mon
kollakube res create pod ceph-mon

wait_for_pods kolla

kollakube res create pod ceph-bootstrap-osd0
pull_containers kolla

wait_for_pods kolla
wait_for_ceph_bootstrap kolla

kollakube res create pod ceph-bootstrap-osd1

wait_for_pods kolla
wait_for_ceph_bootstrap kolla

kollakube res delete pod ceph-bootstrap-osd0
kollakube res delete pod ceph-bootstrap-osd1
kollakube res create pod ceph-osd0
kollakube res create pod ceph-osd1

wait_for_pods kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.client.admin.keyring" > /tmp/$$
rm -f /tmp/$$
kollakube res create pod ceph-admin ceph-rbd

wait_for_pods kolla

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

pull_containers kolla
wait_for_pods kolla

kollakube res delete bootstrap mariadb-bootstrap rabbitmq-bootstrap
kollakube res create pod mariadb memcached rabbitmq

wait_for_pods kolla

kollakube resource create bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

pull_containers kolla
wait_for_pods kolla

kollakube resource delete bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

kollakube res create pod keystone

wait_for_pods kolla

kollakube res create bootstrap nova-create-keystone-user \
    glance-create-keystone-user cinder-create-keystone-user \
    neutron-create-keystone-user \
    nova-create-keystone-endpoint-public \
    glance-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-publicv2 \
    neutron-create-keystone-endpoint-public

wait_for_pods kolla

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

pull_containers kolla
wait_for_pods kolla

mkdir -p $WORKSPACE/logs/
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla

KEYSTONE_CLUSTER_IP=`kubectl get svc keystone-public --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`
KEYSTONE_ADMIN_PASSWD=`grep keystone_admin_password /etc/kolla/passwords.yml \
    | cut -d':' -f2 | sed -e 's/ //'`

cat > ~/keystonerc_admin <<EOF
unset OS_SERVICE_TOKEN
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASSWD
export OS_AUTH_URL=http://$KEYSTONE_CLUSTER_IP:5000/v3
export PS1='[\u@\h \W(keystone_admin)]$ '
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne
EOF

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

pull_containers kolla
wait_for_pods kolla

kollakube res create pod neutron-dhcp-agent neutron-l3-agent-network \
    neutron-openvswitch-agent-network neutron-metadata-agent-network

kollakube res create bootstrap openvswitch-set-external-ip
kollakube res create pod nova-libvirt
kollakube res create pod nova-compute
#kollakube res create pod keepalived

pull_containers kolla
wait_for_pods kolla

kollakube res delete bootstrap openvswitch-set-external-ip

wait_for_pods kolla

kubectl get pods --namespace=kolla

tests/bin/basic_tests.sh
