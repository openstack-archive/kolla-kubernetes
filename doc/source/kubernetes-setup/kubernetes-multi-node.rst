.. kubernetes-multinode:

===========================================
Kubernetes Multinode Guide
===========================================

All Hosts
---------

http://kubernetes.io/docs/getting-started-guides/docker-multinode/#setup-the-master-node

Kubernetes manipulates firewall rules and it should be the only service on
the host doing that or some of the containers will fail.  Disable the firewall
on your host::

  # CentOS
  systemctl stop firewalld
  systemctl disable firewalld

Master node(s)
--------------

  DNS services
    - dnsmasq
    - kube-dns
    - healthz

  Kubernetes services
    - kubernetes-dashboard
    - kube-addon-manager
    - controller-manager
    - apiserver
    - scheduler
    - kube-proxy
    - kubelet

  Network
    - Flannel

Execute the following commands on the node that will be the Kubernetes master::

   git clone https://github.com/kubernetes/kube-deploy
   ./kube-deploy/docker-multinode/master.sh

Minion node(s)
--------------

  Kubernetes services
    - kubelet
    - kube-proxy

  Network
    - Flannel


On each minion run the following commands::

   git clone https://github.com/kubernetes/kube-deploy
   ./kube-deploy/docker-multinode/minion.sh

Check if the Cluster is healthy
===============================

Master node(s)
--------------

Run the ``setup-kubectl.sh`` script which will pull the latest kubectl from
git.

::

  ./kolla-kubernetes/tools/setup-kubectl.sh

Try it out::

   kubectl get services --all-namespaces

To confirm that DNS services are working, you can start a busybox job which will
check if ``kubernetes`` is resolvable from inside of it.  If the job completes,
then DNS is up and running.

::

  kubectl create -f tools/test-dns.yml
  kubectl get jobs
