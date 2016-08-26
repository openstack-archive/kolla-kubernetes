.. multi-node:

=======================================
Kolla Kubernetes Multi-Node Devel Guide
=======================================

wget https://github.com/kubernetes/kubernetes/releases/download/v1.3.5/kubernetes.tar.gz
tar -zxvf kubernetes.tar.gz 
cd kubernetes
export KUBERNETES_PROVIDER=vagrant
export NUM_MINIONS=2
./cluster/kube-up.sh
kubectl get nodes

label one node as compute, another as compute like:

kubectl label node <node1> kolla_controller=v1
kubectl label node <node2> kolla_compute=v1

Then follow the directions in the Multi-Node Guide.
