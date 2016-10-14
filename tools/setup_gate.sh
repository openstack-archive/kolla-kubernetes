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
            kubectl get pods --namespace $1 && trap_error
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
            kubectl get pods --namespace $1 && trap_error
    done
}

function wait_for_vm {
    set +x
    count=0
    while true; do
        val=$(openstack server show $1 -f value -c OS-EXT-STS:vm_state)
        [ $val == "active" ] && break
        [ $val == "error" ] && openstack server show $1 && trap_error
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && trap_error
    done
    set -x
}

function wait_for_vm_ssh {
    set +ex
    count=0
    while true; do
        sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
            StrictHostKeyChecking=no cirros@$1 echo > /dev/null
        [ $? -eq 0 ] && break
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && echo failed to ssh. && trap_error
    done
    set -ex
}

function scp_to_vm {
    sshpass -p 'cubswin:)' scp -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no "$2" cirros@$1:"$3"
}

function scp_from_vm {
    sshpass -p 'cubswin:)' scp -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no cirros@$1:"$2" "$3"
}

function ssh_to_vm {
    sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no cirros@$1 "$2"
}

function wait_for_cinder {
    count=0
    while true; do
        st=$(openstack volume show $1 -f value -c status)
        [ $st != "$2" ] && break
        sleep 1
        count=$((count+1))
        [ $count -gt 30 ] && echo Cinder volume failed. && trap_error
    done
}

function trap_error {
    set +xe
    mkdir -p $WORKSPACE/logs/pods
    mkdir -p $WORKSPACE/logs/svc
    mkdir -p $WORKSPACE/logs/ceph
    mkdir -p $WORKSPACE/logs/openstack
    sudo cp /var/log/messages $WORKSPACE/logs
    sudo cp /var/log/syslog $WORKSPACE/logs
    sudo cp -a /etc/kubernetes $WORKSPACE/logs
    sudo chmod 777 --recursive $WORKSPACE/logs/*
    kubectl get nodes -o yaml > $WORKSPACE/logs/nodes.yaml
    kubectl get pods --all-namespaces -o yaml > $WORKSPACE/logs/pods.yaml
    kubectl get jobs --all-namespaces -o yaml > $WORKSPACE/logs/jobs.yaml
    kubectl get svc --all-namespaces -o yaml > $WORKSPACE/logs/svc.yaml
    kubectl get deployments --all-namespaces -o yaml > \
        $WORKSPACE/logs/deployments.yaml
    kubectl describe node $(hostname -s) > $WORKSPACE/logs/node.txt
    kubectl get pods --all-namespaces -o yaml > $WORKSPACE/logs/pods.yaml
    kubectl get pods --all-namespaces -o json | jq -r \
        '.items[].metadata | .namespace + " " + .name' | while read line; do
        NAMESPACE=$(echo $line | awk '{print $1}')
        NAME=$(echo $line | awk '{print $2}')
        echo $NAME | grep libvirt > /dev/null && \
        kubectl exec $NAME -c main --namespace $NAMESPACE \
            -- /bin/bash -c "virsh secret-list" > \
            $WORKSPACE/logs/virsh-secret-list.txt
        echo $NAME | grep libvirt > /dev/null && \
        kubectl exec $NAME -c main --namespace $NAMESPACE \
            -- /bin/bash -c "cat /var/log/libvirt/qemu/*" > \
            $WORKSPACE/logs/libvirt-vm-logs.txt
        kubectl exec $NAME -c main --namespace $NAMESPACE \
            -- /bin/bash -c "cat /var/log/kolla/*/*.log" > \
            $WORKSPACE/logs/openstack/$NAMESPACE-$NAME.txt
        kubectl describe pod $NAME --namespace $NAMESPACE > \
            $WORKSPACE/logs/pods/$NAMESPACE-$NAME.txt
        kubectl get pod $NAME --namespace $NAMESPACE -o json | jq -r \
            ".spec.containers[].name" | while read CON; do
            kubectl logs $NAME -c $CON --namespace $NAMESPACE > \
                $WORKSPACE/logs/pods/$NAMESPACE-$NAME-$CON.txt
        done
    done
    kubectl get svc -o json --all-namespaces | jq -r \
        '.items[].metadata | .namespace + " " + .name' | while read line; do
        NAMESPACE=$(echo $line | awk '{print $1}')
        NAME=$(echo $line | awk '{print $2}')
        kubectl describe svc $NAME --namespace $NAMESPACE > \
            $WORKSPACE/logs/svc/$NAMESPACE-$NAME.txt
    done
    sudo iptables-save > $WORKSPACE/logs/iptables.txt
    sudo ip a > $WORKSPACE/logs/ip.txt
    sudo route -n > $WORKSPACE/logs/routes.txt
    cp /etc/kolla/passwords.yml $WORKSPACE/logs/
    kubectl get pods -l system=openvswitch-vswitchd-network --namespace=kolla \
        | while read line; do
        kubectl logs $line --namespace=kolla -c initialize-ovs-vswitchd >> \
            $WORKSPACE/logs/ovs-init.txt
    done
    openstack catalog list > $WORKSPACE/logs/openstack-catalog.txt
    str="timeout 6s ceph -s"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
    sudo journalctl -u kubelet > $WORKSPACE/logs/kubelet.txt
    str="timeout 6s ceph pg 1.1 query"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
        > $WORKSPACE/logs/ceph/pg1.1.txt
    str="timeout 6s ceph osd tree"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
        > $WORKSPACE/logs/ceph/osdtree.txt
    str="timeout 6s ceph health"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
    str="cat /var/log/kolla/ceph/*.log"
    kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c "$str" \
        > $WORKSPACE/logs/ceph/osd.txt
    str="timeout 6s ceph pg dump"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
        > $WORKSPACE/logs/ceph/pgdump.txt
    str="ceph osd crush tree"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
        > $WORKSPACE/logs/ceph/crushtree.txt
    df -h > $WORKSPACE/logs/df.txt
    dmesg > $WORKSPACE/logs/dmesg
    kubectl get secret ceph-client-nova-keyring --namespace=kolla -o yaml
    kubectl get secret nova-libvirt-bin --namespace=kolla -o yaml
    openstack volume list > $WORKSPACE/logs/volumes.txt
    cp -a /etc/kolla $WORKSPACE/logs/
    exit -1
}

[ "x$4" == "xiscsi" ] && echo "iscsi support pending..." && exit 0

trap 'trap_error "$?"' ERR

echo Setting up the gate...
env
echo Setting up the gate...

sudo iptables-save

l=$(sudo iptables -L INPUT --line-numbers | grep openstack-INPUT | \
    awk '{print $1}')
sudo iptables -D INPUT $l

ip a | sed '/^[^1-9]/d;' | awk '{print $2}' | sed 's/://' | \
    grep -v '^lo$' | while read line; do
    sudo iptables -I INPUT 1 -i $line -j openstack-INPUT
done

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

if [ -f /etc/redhat-release ]; then
    cat > /tmp/setup.$$ <<"EOF"
setenforce 0
cat <<"EOEF" > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOEF
yum install -y docker kubelet kubeadm kubectl kubernetes-cni sshpass
systemctl start kubelet
EOF
else
    cat > /tmp/setup.$$ <<"EOF"
apt-get install -y apt-transport-https
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni sshpass
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
mkdir -p /data/kolla
df -h
dd if=/dev/zero of=/data/kolla/ceph-osd0.img bs=5M count=1024
dd if=/dev/zero of=/data/kolla/ceph-osd1.img bs=5M count=1024
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/ceph-osd0.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 512m
parted $LOOP mkpart 2 513m 100%
dd if=/dev/zero of=/data/kolla/ceph-osd1.img bs=5M count=1024
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/ceph-osd1.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 512m
parted $LOOP mkpart 2 513m 100%
partprobe
systemctl start docker
kubeadm init --service-cidr 172.16.128.0/24
sed -i 's/100.64.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl stop kubelet
systemctl restart docker
systemctl start kubelet
EOF

sudo bash /tmp/setup.$$

sudo docker ps -a

count=0
while true; do
    kubectl get pods > /dev/null 2>&1 && break || true
    sleep 1
    count=$((count + 1))
    [ $count -gt 30 ] && echo kube-apiserver failed to come back up. && exit -1
done

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

kubectl create namespace kolla
tools/secret-generator.py create

wait_for_pods kube-system

kubectl describe node $NODE

kollakube tmpl pv mariadb

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

mkdir -p $WORKSPACE/logs/

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
    trap_error
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

curl -o cirros.qcow2 \
    http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
echo testing cluster glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`:9292/
echo testing external glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`:9292/
timeout 120s openstack image create --file cirros.qcow2 --disk-format qcow2 \
     --container-format bare 'CirrOS'

neutron net-create --provider:physical_network=physnet1 \
    --provider:network_type=flat external
neutron net-update --router:external=True external
neutron subnet-create --gateway 172.18.0.1 --disable-dhcp \
    --allocation-pool start=172.18.0.65,end=172.18.0.254 \
    --name external external 172.18.0.0/24
neutron router-create admin
neutron router-gateway-set admin external

neutron net-create admin
neutron subnet-create --gateway=172.18.1.1 \
    --allocation-pool start=172.18.1.65,end=172.18.1.254 \
    --name admin admin 172.18.1.0/24
neutron router-interface-add admin admin
neutron security-group-rule-create --protocol icmp \
    --direction ingress default
neutron security-group-rule-create --protocol tcp \
    --port-range-min 22 --port-range-max 22 \
    --direction ingress default

openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test
openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test2

wait_for_vm test
wait_for_vm test2

openstack volume create --size 1 test

wait_for_cinder test creating

openstack server add volume test test

FIP=$(openstack floating ip create external -f value -c floating_ip_address)
FIP2=$(openstack floating ip create external -f value -c floating_ip_address)

openstack server add floating ip test $FIP
openstack server add floating ip test2 $FIP2

openstack server list

wait_for_vm_ssh $FIP

sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
    StrictHostKeyChecking=no cirros@$FIP curl 169.254.169.254

sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
    StrictHostKeyChecking=no cirros@$FIP ping -c 4 $FIP2

openstack volume show test -f value -c status
TESTSTR=$(uuidgen)
cat > /tmp/$$ <<EOF
#!/bin/sh -xe
mkdir /tmp/mnt
sudo /sbin/mkfs.vfat /dev/vdb
sudo mount /dev/vdb /tmp/mnt
sudo /bin/sh -c 'echo $TESTSTR > /tmp/mnt/test.txt'
sudo umount /tmp/mnt
EOF
chmod +x /tmp/$$

scp_to_vm $FIP /tmp/$$ /tmp/script
ssh_to_vm $FIP "/tmp/script"

openstack server remove volume test test
wait_for_cinder test in-use
wait_for_cinder test detaching
openstack server add volume test2 test
wait_for_cinder test available

cat > /tmp/$$ <<EOF
#!/bin/sh -xe
mkdir /tmp/mnt
sudo mount /dev/vdb /tmp/mnt
sudo cat /tmp/mnt/test.txt
sudo cp /tmp/mnt/test.txt /tmp
sudo chown cirros /tmp/test.txt
EOF
chmod +x /tmp/$$

scp_to_vm $FIP2 /tmp/$$ /tmp/script
ssh_to_vm $FIP2 "/tmp/script"
scp_from_vm $FIP2 /tmp/test.txt /tmp/$$.2

diff -u <(echo $TESTSTR) /tmp/$$.2
