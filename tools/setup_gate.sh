#!/bin/bash -xe

function trap_error {
	set +e
	mkdir -p $WORKSPACE/logs
	sudo cp /etc/sysconfig/docker-storage /etc/sysconfig/docker-storage-setup $WORKSPACE/logs
	sudo cp /var/log/messages $WORKSPACE/logs
        sudo chmod 777 $WORKSPACE/logs/*
	exit -1
}

trap 'trap_error "$?"' ERR

echo Setting up the gate...
env
echo Setting up the gate...

git checkout https://github.com/openstack/kolla
sudo ln -s `pwd`/kolla/etc/kollla /etc/kolla
sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes

if [ -f /etc/redhat-release ];
then
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
	docker ps -a && break || true
        sleep 1
        COUNT=$((COUNT+1))
        [ $COUNT -gt 5 ] && break
done

[ $COUNT -gt 5 ] && echo docker failed to starrt. && error_exit

sudo kubeadm init

kubectl taint nodes --all dedicated-

kubectl get pods

