Kolla Kubernetes All In One Guide
=================================

Single-node Kubernetes setup
----------------------------
http://kubernetes.io/docs/getting-started-guides/docker/

The hypekube container runs the following services:
  - kube-apiproxy (The master)
  - kublet (Starts/Stops services & syncs config)
  - kube-scheduler (Resource manager)
  - kube-controller-manger (Manages desired state by monitoring the RC)
  - kube-proxy (Exposes the services on each node)

::

   docker run --volume=/:/rootfs:ro --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:rw --volume=/var/lib/kubelet/:/var/lib/kubelet:rw --volume=/var/run:/var/run:rw --net=host --pid=host --privileged=true --name=kubelet -d gcr.io/google_containers/hyperkube-amd64:v1.2.0 /hyperkube kubelet --containerized --hostname-override="127.0.0.1" --address="0.0.0.0" --api-servers=http://localhost:8080 --config=/etc/kubernetes/manifests --cluster-dns=10.0.0.10 --cluster-domain=cluster.local --allow-privileged=true --v=2

Download kubectl.

::

   wget http://storage.googleapis.com/kubernetes-release/release/v1.2.0/bin/linux/amd64/kubectl
   chmod 755 kubectl
   PATH=$PATH:`pwd`

Try it out.

::

   kubectl get nodes
