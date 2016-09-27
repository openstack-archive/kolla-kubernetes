#!/bin/bash -xe

echo Setting up the gate...
env
echo Setting up the gate...

if [ -f /etc/redhat-release ];
then
	cat > /tmp/setup.$$ <<"EOF"
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
systemctl start docker
systemctl start kubelet
EOF
else
        cat > /tmp/setup.$$ <<"EOF"
apt-get install -y docker
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni
EOF
fi
sudo bash /tmp/setup.$$

docker ps -a

kubeadm init

kubectl taint nodes --all dedicated-

kubectl get pods
