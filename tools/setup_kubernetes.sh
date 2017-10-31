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
yum install -y docker kubeadm kubelet kubectl kubernetes-cni ebtables
sed -i 's/10.96.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
EOF
else
    cat > /tmp/setup.$$ <<"EOF"
apt-get install -y apt-transport-https
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y docker.io kubeadm kubelet kubectl kubernetes-cni
cgroup_driver=$(docker info | grep "Cgroup Driver" | awk '{print $3}')
sed -i 's|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver='$cgroup_driver' |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's/10.96.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
EOF
fi

cat >> /tmp/setup.$$ <<"EOF"
modprobe br_netfilter || true
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
systemctl daemon-reload
systemctl start docker
systemctl restart kubelet
EOF

if [ "$1" == "master" ]; then
    cat >> /tmp/setup.$$ <<"EOF"
[ -d /etc/kubernetes/manifests ] && rmdir /etc/kubernetes/manifests || true
kubeadm init --skip-preflight-checks --service-cidr 172.16.128.0/24 --pod-network-cidr 172.16.132.0/22 \
             --apiserver-advertise-address $(cat /etc/nodepool/primary_node_private) | tee /tmp/kubeout
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $4}' > /etc/kubernetes/token.txt
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $5}' > /etc/kubernetes/ip.txt
grep 'kubeadm join --token' /tmp/kubeout | awk '{print $7}' > /etc/kubernetes/cahash.txt
rm -f /tmp/kubeout
EOF
else
    cat >> /tmp/setup.$$ <<EOF
kubeadm join --token "$2" "$3" --skip-preflight-checks --discovery-token-ca-cert-hash "$4"
EOF
fi
cat >> /tmp/setup.$$ <<"EOF"
EOF
sudo bash /tmp/setup.$$
sudo docker ps -a
sudo /usr/bin/kubelet --version

if [ "$1" == "master" ]; then
    mkdir -p ~/.kube
    sudo cp /etc/kubernetes/admin.conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    tools/wait_for_kube_control_plane.sh

# NOTE(sbezverk/kfox111) This is a horible hack to get k8s 1.6+ working. This should be
# removed in favor of more fine grained rules.
# It should be run on the master only when it is up, hence moving it inside of if
kubectl apply -f <(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: system:masters
- kind: Group
  name: system:authenticated
- kind: Group
  name: system:unauthenticated
EOF
)
    set -e
fi
