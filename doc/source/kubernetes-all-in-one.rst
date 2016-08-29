.. kubernetes-all-in-one:

=================================
Kolla Kubernetes All In One Guide
=================================

Single-node Kubernetes setup
============================

DNS services
  - dnsmasq
  - kube-dns
  - healthz

Hypercube service
  - kubernetes-dashboard
  - kube-addon-manager
  - controller-manager
  - apiserver
  - scheduler
  - kube-proxy
  - kubelet

http://kubernetes.io/docs/getting-started-guides/docker-multinode/#setup-the-master-node

Execute the following commands to create an all-in-one Kubernetes setup::

   git clone https://github.com/kubernetes/kube-deploy
   ./kube-deploy/docker-multinode/master.sh

Download kubectl::

   wget http://storage.googleapis.com/kubernetes-release/release/v1.2.4/bin/linux/amd64/kubectl
   chmod 755 kubectl
   PATH=$PATH:`pwd`

Try it out::

   kubectl get services --all-namespaces

To check that DNS services are working, you can start a busybox pod and try
and resolve ``kubernetes`` from inside of it::

  kubectl create -f tools/busybox.yaml
  kubectl exec busybox -- nslookup kubernetes
