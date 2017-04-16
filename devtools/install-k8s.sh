sudo yum install -y docker ebtables kubeadm kubectl kubelet kubernetes-cni
sudo systemctl enable docker
sudo systemctl start docker
CGROUP_DRIVER=$(sudo docker info | grep "Cgroup Driver" | awk '{print $3}')
sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=$CGROUP_DRIVER --enable-cri=false |g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo sed -i 's/10.96.0.10/10.3.3.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo systemctl daemon-reload
sudo systemctl stop kubelet
sudo systemctl enable kubelet
sudo systemctl start kubelet
sudo kubeadm init --pod-network-cidr=10.1.0.0/16 --service-cidr=10.3.3.0/24
mkdir -p $HOME/.kube
sudo -H cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo -H chown $(id -u):$(id -g) $HOME/.kube/config
curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/kubeadm/1.6/canal.yaml -o canal.yaml
sed -i "s@192.168.0.0/16@10.1.0.0/16@" canal.yaml
sed -i "s@10.96.232.136@10.3.3.100@" canal.yaml
kubectl apply -f canal.yaml
kubectl taint nodes --all=true node-role.kubernetes.io/master:NoSchedule-
