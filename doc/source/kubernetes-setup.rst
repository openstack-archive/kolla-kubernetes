.. kubernetes-setup:

============================
Kolla Kubernetes Setup Guide
============================

The most well tested setup guide for Kuberentes is the
::doc:: `minikube-quickstart`.  It will walk through the entire setup
including getting Kubernetes and OpenStack deployed.  This guide
is an alternative method for starting Kubernetes.

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

Kubernetes manipulates firewall rules so we want it to be the only service on
the host doing that or some of the containers will fail.  Disable the firewall
on your host::

  # CentOS
  systemctl stop firewalld
  systemctl disable firewalld

Execute the following commands to create an all-in-one Kubernetes setup::

   git clone https://github.com/kubernetes/kube-deploy
   ./kube-deploy/docker-multinode/master.sh

The ``setup-kubectl.sh`` script will pull the latest kubectl from git::

  git clone https://github.com/openstack/kolla-kubernetes
  cd kolla-kubernetes
  ./tools/setup-kubectl.sh

Try it out::

   kubectl get services --all-namespaces

To confirm that DNS services are working, you can start a busybox job which will
check if ``kubernetes`` is resolvable from inside of it.  If the job completes,
then DNS is up and running.

::

  kubectl create -f tools/test-dns.yml
  kubectl get jobs
