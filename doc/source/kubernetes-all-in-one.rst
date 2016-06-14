.. kubernetes-all-in-one:

=================================
Kolla Kubernetes All In One Guide
=================================

Single-node Kubernetes setup
============================

http://kubernetes.io/docs/getting-started-guides/docker/

The hyperkube container runs the following services:
  - kube-apiserver (The master)
  - kubelet (Starts/Stops pods and containers also syncs config)
  - kube-scheduler (Resource manager)
  - kube-controller-manager (Manages desired state by monitoring the RC)
  - kube-proxy (Exposes the services on each node)
  - etcd (Distributed key-value store)

You will need to know your machine's IP address in order to set up DNS
properly.  You can use ``hostname -i`` to check.  At the end of the docker run
command for hyperkube, there's a blank ``--cluster-dns=`` paramater that you
need to set your system's IP address to.  (e.g. ``--cluster-dns=192.0.2.0``)

::

   docker run --volume=/:/rootfs:ro --volume=/sys:/sys:rw --volume=/var/lib/docker/:/var/lib/docker:rw --volume=/var/lib/kubelet/:/var/lib/kubelet:rw,shared --volume=/var/run:/var/run:rw --net=host --pid=host --privileged=true --name=kubelet -d gcr.io/google_containers/hyperkube-amd64:v1.2.4 /hyperkube kubelet --resolv-conf="" --containerized --hostname-override="127.0.0.1" --address="0.0.0.0" --api-servers=http://localhost:8080 --config=/etc/kubernetes/manifests --cluster-domain=openstack --allow-privileged=true --v=2 --cluster-dns=

Set up SkyDNS::

    docker run -d --net=host --restart=always gcr.io/google_containers/kube2sky:1.12 -v=10 -logtostderr=true -domain=openstack.local -etcd-server="http://127.0.0.1:4001"
    docker run -d --net=host --restart=always -e ETCD_MACHINES="http://127.0.0.1:4001" -e SKYDNS_DOMAIN="openstack.local" -e SKYDNS_ADDR="0.0.0.0:53" -e SKYDNS_NAMESERVERS="8.8.8.8:53,8.8.4.4:53" gcr.io/google_containers/skydns:2015-10-13-8c72f8c

Download kubectl::

   wget http://storage.googleapis.com/kubernetes-release/release/v1.2.4/bin/linux/amd64/kubectl
   chmod 755 kubectl
   PATH=$PATH:`pwd`

Create a Kubernetes cluster configuration::

  kubectl config set-cluster kolla --server=http://localhost:8080
  kubectl config set-context kolla --cluster=kolla
  kubectl config use-context kolla

Try it out::

   kubectl get nodes
