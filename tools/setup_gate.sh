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
    end=$((end + 240))
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

function trap_error {
    set +xe
    mkdir -p $WORKSPACE/logs/pods
    sudo cp /var/log/messages $WORKSPACE/logs
    sudo cp /var/log/syslog $WORKSPACE/logs
    sudo chmod 777 $WORKSPACE/logs/*
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
        kubectl describe pod $NAME --namespace $NAMESPACE > \
            $WORKSPACE/logs/pods/$NAMESPACE-$NAME.txt
        kubectl get pod $NAME --namespace $NAMESPACE -o json | jq -r \
            ".spec.containers[].name" | while read CON; do
            kubectl logs $NAME -c $CON --namespace $NAMESPACE > \
                $WORKSPACE/logs/pods/$NAMESPACE-$NAME-$CON.txt
        done
    done
    sudo iptables-save > $WORKSPACE/logs/iptables.txt
    sudo ip a > $WORKSPACE/logs/ip.txt
    sudo route -n > $WORKSPACE/logs/routes.txt
    cp /etc/kolla/passwords.yml $WORKSPACE/logs/
    exit -1
}

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

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq
else
    sudo apt-get update
    sudo apt-get install -y crudini jq
fi

pushd kolla;
pip install pip --upgrade
pip install "ansible<2.1"
pip install -r requirements.txt
pip install pyyaml
./tools/generate_passwords.py
./tools/kolla-ansible genconfig
popd
pip install -r requirements.txt
pip install .

crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
sed -i \
    '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\n'\
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
yum install -y docker kubelet kubeadm kubectl kubernetes-cni
systemctl start kubelet
EOF
else
    cat > /tmp/setup.$$ <<"EOF"
apt-get install -y apt-transport-https
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
mkdir -p /data/kolla
dd if=/dev/zero of=/data/kolla/ceph-osd0.img bs=1 count=0 seek=3G
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/ceph-osd0.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 512m
parted $LOOP mkpart 2 513m 100%
partprobe
exit
exit
EOF

sudo bash /tmp/setup.$$

sudo systemctl start docker

sudo kubeadm init --service-cidr 172.16.128.0/24

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

curl $URL -o /tmp/canal.yaml

sed -i "s@192.168.0.0/16@172.16.130.0/23@" /tmp/canal.yaml
sed -i "s@100.78.232.136@172.16.128.10@" /tmp/canal.yaml

kubectl create -f /tmp/canal.yaml

kubectl create namespace kolla
tools/secret-generator.py create

wait_for_pods kube-system

kubectl describe node $NODE

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
    cinder-scheduler cinder-volume ceph-mon ceph-osd;

kollakube res create bootstrap ceph-bootstrap-initial-mon

pull_containers kolla
wait_for_pods kolla

tools/setup-ceph-secrets.sh
kollakube res delete bootstrap ceph-bootstrap-initial-mon
kollakube res create pod ceph-mon

wait_for_pods kolla

kollakube res create pod ceph-bootstrap-osd

mkdir -p $WORKSPACE/logs/

pull_containers kolla
wait_for_pods kolla

kollakube res delete pod ceph-bootstrap-osd
kollakube res create pod ceph-osd

wait_for_pods kolla

for x in images volumes vms; do
    kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool create $x 64"
done
str="ceph auth get-or-create client.glance mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=images'"
kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-glance-keyring --namespace=kolla\
    --from-file=ceph.client.glance.keyring=/tmp/$$
str="ceph auth get-or-create client.cinder mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes'"
kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-cinder-keyring --namespace=kolla\
    --from-file=ceph.client.cinder.keyring=/tmp/$$
str="ceph auth get-or-create client.nova mon 'allow r' osd 'allow "
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes, "
str="$str allow rwx pool=vms, allow rwx pool=images'"
kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-nova-keyring --namespace=kolla \
    --from-file=ceph.client.nova.keyring=/tmp/$$
kubectl create secret generic nova-libvirt-bin --namespace=kolla \
    --from-file=data=<(awk '{if($1 == "key"){print $3}}' /tmp/$$ |
    tr -d '\n')
kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
rm -f /tmp/$$
kollakube res create secret nova-libvirt

for x in mariadb rabbitmq glance; do
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

kollakube res create bootstrap glance-create-db glance-endpoints \
    glance-manage-db nova-create-api-db nova-create-endpoints nova-create-db \
    neutron-create-db neutron-endpoints neutron-manage-db cinder-create-db \
    cinder-create-endpoints cinder-manage-db

pull_containers kolla
wait_for_pods kolla

kollakube res delete bootstrap glance-create-db glance-endpoints \
    glance-manage-db nova-create-api-db nova-create-endpoints nova-create-db \
    neutron-create-db neutron-endpoints neutron-manage-db cinder-create-db \
    cinder-create-endpoints cinder-manage-db

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

pull_containers kolla
wait_for_pods kolla

kollakube res delete bootstrap openvswitch-set-external-ip

wait_for_pods kolla

kubectl get pods --namespace=kolla
