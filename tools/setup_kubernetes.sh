#!/bin/bash -e

if [ -f /etc/redhat-release ]; then
    cat > /tmp/setup.$$ <<"EOF"
setenforce 0
cat <<"EOEF" > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOEF
yum install -y docker kubeadm-1.6.0-0.x86_64 kubelet kubectl kubernetes-cni ebtables
sed -i 's|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=systemd |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's|KUBELET_NETWORK_ARGS=.*|KUBELET_NETWORK_ARGS=" |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl start docker
systemctl start kubelet
EOF
else
    cat > /tmp/setup.$$ <<"EOF"
apt-get install -y apt-transport-https
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y docker.io kubeadm kubelet kubectl kubernetes-cni
sed -i 's|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=systemd |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's|KUBELET_NETWORK_ARGS=.*|KUBELET_NETWORK_ARGS=" |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo service kubelet restart
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
systemctl start docker
EOF
if [ "$1" == "master" ]; then
    cat >> /tmp/setup.$$ <<"EOF"
[ -d /etc/kubernetes/manifests ] && rmdir /etc/kubernetes/manifests || true
kubeadm init --skip-preflight-checks --service-cidr 172.16.128.0/24 \
             --apiserver-advertise-address $(cat /etc/nodepool/primary_node_private) | tee /tmp/kubeout
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $4}' > /etc/kubernetes/token.txt
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $5}' > /etc/kubernetes/ip.txt
rm -f /tmp/kubeout
EOF
else
    cat >> /tmp/setup.$$ <<EOF
kubeadm join --token "$2" "$3" --skip-preflight-checks
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
sed -i 's/10.96.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
#sed -i 's|RBAC|AlwaysAllow|g' /etc/kubernetes/manifests/kube-apiserver.yaml
#sed -i 's|insecure-port=0|insecure-port=8080|g' \
#        /etc/kubernetes/manifests/kube-apiserver.yaml 
systemctl daemon-reload
systemctl stop kubelet
systemctl restart docker
systemctl start kubelet
EOF
sudo bash /tmp/setup.$$
sudo docker ps -a
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config 
sudo chown $(id -u):$(id -g) ~/.kube/config
sudo netstat -tunlp
kubectl config view

if [ "$1" == "master" ]; then
    count=0
    while true; do
        kubectl get pods -n kube-system > /dev/null 2>&1 && break || true
        sleep 1
        count=$((count + 1))
        [ $count -gt 30 ] && echo kube-apiserver failed to come back up. && exit -1
    done
fi
