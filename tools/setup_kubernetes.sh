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

# TODO(sdake) unpin kubernetes from a known working RPM packaged version
# NOTE(sdake) These pins are known good working pins for the RPM packaging for
#             Kubernetes. Kubernetes 1.6.0 is incompatible with kubeadm 1.6.0.
yum install -y docker kubelet-1.5.4-0.x86_64 kubeadm-1.6.0-0.alpha.0.2074.a092d8e0f95f52 kubectl-1.5.4-0.x86_64 kubernetes-cni-0.3.0.1-0.07a8a2.x86_64 ebtables
systemctl start kubelet
EOF
else
    cat > /tmp/setup.$$ <<"EOF"
apt-get install -y apt-transport-https
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update

# TODO(sdake) unpin kubernetes from a known working RPM packaged version
# NOTE(sdake) These pins are known good working pins for the DEB packaging for
#             Kubernetes. Kubernetes 1.6.0 is incompatible with kubeadm 1.6.0.
apt-get install -y docker.io kubelet=1.5.6-00 kubeadm=1.5.6-00 kubectl=1.5.6-00 kubernetes-cni=0.5.1-00
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
systemctl start docker
EOF
if [ "$1" == "master" ]; then
    cat >> /tmp/setup.$$ <<"EOF"
[ -d /etc/kubernetes/manifests ] && rmdir /etc/kubernetes/manifests || true
kubeadm init --skip-preflight-checks --service-cidr 172.16.128.0/24 --api-advertise-addresses $(cat /etc/nodepool/primary_node_private) | tee /tmp/kubeout
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $3}' | sed 's/[^=]*=//' > /etc/kubernetes/token.txt
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $4}' > /etc/kubernetes/ip.txt
rm -f /tmp/kubeout
EOF
else
    cat >> /tmp/setup.$$ <<EOF
kubeadm join --token "$2" "$3" --skip-preflight-checks
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
sed -i 's/10.96.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl stop kubelet
systemctl restart docker
systemctl start kubelet
EOF
sudo bash /tmp/setup.$$
sudo docker ps -a

if [ "$1" == "master" ]; then
    count=0
    while true; do
        kubectl get pods > /dev/null 2>&1 && break || true
        sleep 1
        count=$((count + 1))
        [ $count -gt 30 ] && echo kube-apiserver failed to come back up. && exit -1
    done
fi
