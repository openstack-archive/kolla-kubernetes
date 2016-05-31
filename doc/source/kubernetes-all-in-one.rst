.. kubernetes-all-in-one:

=================================
Kolla Kubernetes All In One Guide
=================================

Single-node Kubernetes setup
============================

http://kubernetes.io/docs/getting-started-guides/docker/

The hyperkube container runs the following services:
  - kube-apiserver (The master)
  - kublet (Starts/Stops pods and containers also syncs config)
  - kube-scheduler (Resource manager)
  - kube-controller-manger (Manages desired state by monitoring the RC)
  - kube-proxy (Exposes the services on each node)
  - etcd (Distributed key-value store)

::

   docker run --volume=/:/rootfs:ro --volume=/sys:/sys:rw --volume=/var/lib/docker/:/var/lib/docker:rw --volume=/var/lib/kubelet/:/var/lib/kubelet:rw,shared --volume=/var/run:/var/run:rw --net=host --pid=host --privileged=true --name=kubelet -d gcr.io/google_containers/hyperkube-amd64:v1.2.4 /hyperkube kubelet --resolv-conf="" --containerized --hostname-override="127.0.0.1" --address="0.0.0.0" --api-servers=http://localhost:8080 --config=/etc/kubernetes/manifests --cluster-dns=10.0.0.10 --cluster-domain=openstack --allow-privileged=true --v=2

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
