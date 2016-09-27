#!/bin/bash -xe

function trap_error {
    set +e
    mkdir -p $WORKSPACE/logs
    sudo cp /var/log/messages $WORKSPACE/logs
    sudo cp /var/log/syslog $WORKSPACE/logs
    sudo chmod 777 $WORKSPACE/logs/*
    exit -1
}

trap 'trap_error "$?"' ERR

echo Setting up the gate...
env
echo Setting up the gate...

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

sudo bash /tmp/setup.$$

sudo systemctl start docker

COUNT=0
while true; do
    sudo docker ps -a && break || true
    sleep 1
    COUNT=$((COUNT+1))
    [ $COUNT -gt 5 ] && break
done

[ $COUNT -gt 5 ] && echo docker failed to starrt. && exit -1

sudo kubeadm init

kubectl taint nodes --all dedicated-

NODE=$(hostname -s)

cat tests/conf/ceph-all-in-one/kolla_kubernetes_config \
    >> etc/kolla-kubernetes/kolla-kubernetes.yml

sed -i "s/initial_mon:.*/initial_mon: $NODE/" \
    etc/kolla-kubernetes/kolla-kubernetes.yml

kubectl label node $NODE kolla_controller=true
kubectl label node $NODE kolla_compute=true

kubectl create -f https://git.io/weave-kube

kubectl create namespace kolla
tools/secret-generator.py create

docker pull kfox1111/centos-binary-kolla-toolbox:trunk-sometime > /dev/null

sleep 30;

kubectl describe node $NODE

tools/setup-resolv-conf.sh & pid=$!

sleep 30;

kubectl get pods --all-namespaces -o wide

if [ $(ps -hp $pid | wc -l) -eq 1 ]; then
    kubectl describe pod fetchresolv --namespace=kolla
    exit -1
fi

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume ceph-mon ceph-osd;

