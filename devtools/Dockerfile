FROM CentOS: 7.3
MAINTAINER surya.singh@nectechnologies.in

RUN sudo setenforce 0 \
    && sudo sed -i 's/enforcing/permissive/g' /etc/selinux/config \
    && sudo systemctl stop firewalld \
    && sudo systemctl disable firewalld
    && sudo tee /etc/yum.repos.d/kubernetes.repo<<EOF \
        [kubernetes] \
        name=Kubernetes \
        baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64 \
        enabled=1 \
        gpgcheck=0 \
        repo_gpgcheck=1 \
        gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg \
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg \
        EOF \
    && sudo yum install -y docker ebtables kubeadm kubectl kubelet kubernetes-cni git gcc \

    && sudo systemctl enable docker \
    && sudo systemctl start docker \
    && CGROUP_DRIVER=$(sudo docker info | grep "Cgroup Driver" | awk '{print $3}') \
    && sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=$CGROUP_DRIVER \ 
       --enable-cri=false |g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf \
#Setup the DNS server with the service CIDR
    && sudo sed -i 's/10.96.0.10/10.3.3.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf \
    && mkdir -p $HOME/.kube \
    && sudo -H cp /etc/kubernetes/admin.conf $HOME/.kube/config \
    && sudo -H chown $(id -u):$(id -g) $HOME/.kube/config \
    && curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/kubeadm/1.6/canal.yaml -o canal.yaml \
    && sed -i "s@192.168.0.0/16@10.1.0.0/16@" canal.yaml \
    && sed -i "s@10.96.232.136@10.3.3.100@" canal.yaml \
    && kubectl apply -f canal.yaml \
    && kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

