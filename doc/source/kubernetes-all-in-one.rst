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

Execute the following commands to create an all-in-one Kubernetes setup with DNS.

::

   # Get the IP addr of the local host’s docker0 bridge, (use for Hyperkube DNS)
   export DNS_SERVER_IP=`ip addr show dev docker0 | grep inet | awk '{print $2}'| cut -d'/' -f1`
   export CLUSTER_DOMAIN="openstack.local"

   # Start Hyperkube
   docker run --volume=/:/rootfs:ro --volume=/sys:/sys:rw --volume=/var/lib/docker/:/var/lib/docker:rw --volume=/var/lib/kubelet/:/var/lib/kubelet:rw,shared --volume=/var/run:/var/run:rw --net=host --pid=host --privileged=true --name=kubelet -d gcr.io/google_containers/hyperkube-amd64:v1.3.0 /hyperkube kubelet --resolv-conf="" --containerized --hostname-override="127.0.0.1" --address="0.0.0.0" --api-servers=http://localhost:8080 --config=/etc/kubernetes/manifests --cluster-domain=${CLUSTER_DOMAIN} --allow-privileged=true --v=2 --cluster-dns=${DNS_SERVER_IP}

   # Start Kube2Sky on localhost (must start before skydns)
   docker run -d --net=host --restart=always gcr.io/google_containers/kube2sky:1.12 -v=10 -logtostderr=true -domain=${CLUSTER_DOMAIN} -etcd-server="http://127.0.0.1:4001"

   # Start SkyDNS on localhost (must start after kube2sky)
   docker run -d --net=host --restart=always -e ETCD_MACHINES="http://127.0.0.1:4001" -e SKYDNS_DOMAIN="${CLUSTER_DOMAIN}." -e SKYDNS_ADDR="0.0.0.0:53" -e SKYDNS_NAMESERVERS="8.8.8.8:53,8.8.4.4:53" gcr.io/google_containers/skydns:2015-10-13-8c72f8c


SkyDNS as configured above will any external DNS requests through to the Google
DNS servers, which should work under most circumstances.  You may change the
DNS servers 8.8.8.8 and 8.8.4.4 to custom DNS providers if necessary.

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


Debugging
=========

kube2sky
--------

kube2sky queries Kubernetes and builds out the necessary etcd records for
SkyDNS to use.

To check to see if the Kubernetes service has been copied over from Kubernetes
to SkyDNS, you can check the etcd::

    curl http://127.0.0.1:4001/v2/keys/skydns/local/openstack/svc/default/kubernetes

You should see something like this::

    {"action":"get","node":{"key":"/skydns/local/openstack/svc/default/kubernetes","dir":true,"nodes":[{"key":"/skydns/local/openstack/svc/default/kubernetes/c88f1059","value":"{\"host\":\"10.0.0.1\",\"priority\":10,\"weight\":10,\"ttl\":30,\"targetstrip\":0}","modifiedIndex":137,"createdIndex":137}],"modifiedIndex":92,"createdIndex":92}}

That is the DNS record for the Kubernetes service.

SkyDNS
------

SkyDNS is a DNS server that serves up data stored in etcd.

After you have verified that kube2sky is creating the necessary records in
etcd, you can check to see if the SkyDNS server is responding::

    nslookup kubernetes.default.svc.openstack.local 127.0.0.1

You should see something like this::

    Server:   127.0.0.1
    Address:  127.0.0.1#53

    Name: kubernetes.default.svc.openstack.local
    Address: 10.0.0.1

From inside a Kubernetes pod, you can use::

    nslookup kubernetes
