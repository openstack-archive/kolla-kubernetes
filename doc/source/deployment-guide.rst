================================================
Bare Metal Deployment Guide for kolla-kubernetes
================================================

.. warning::

   This documentation is under construction and some browsers do not update
   on changes to docs.openstack.org.  To resolve this problem, click refresh
   on the browser. The docs do work perfectly if followed but If you still run
   into trouble, please join #openstack-kolla and we can learn together how to
   solve whatever issues faced.  Likely others in the community face the same
   issues.

.. note::

   This document was tested only against CentOS 7.3 Host OS and AIO environments.
   All the steps should be run as non-root user. If you follow this guide as the
   root user, helm cannot be found in ``/usr/local/bin/`` because the path ``/usr/local/bin``
   is not defaulted to enabled in CentOS 7.

Introduction
============

There are many ways to deploy Kubernetes.  This guide has been tested only with
kubeadm.  The documentation for kubeadm is here:

https://kubernetes.io/docs/getting-started-guides/kubeadm/

Here is a video shown at a Kubernetes specific meetup on February 15th, 2017:
https://youtu.be/rHCCUP2odd8

There are two steps to deploying kolla-kubernetes.  The first step involves
deploying Kubernetes.  The second step involves deploying Kolla that is
compatible with Kubernetes.

Host machine requirements
=========================

The host machine must satisfy the following minimum requirements:

- 2 network interfaces
- 8GB main memory
- 40GB disk space

Dependencies::

    docker == 1.12.6
    helm >= 2.2.3
    kubectl >= 1.6.2
    kubeadm >= 1.6.2
    kubelet >= 1.6.2
    kubernetes-cni >= 0.5.1

.. note::

   When working with Kubernetes it is considered a useful practice to open a
   unique terminal window and run the command that watches all Kubernetes's
   processes.  This operation will show changes as they occur within
   Kubernetes. This is referred to as the `watch terminal` in this
   documentation::

     watch -d kubectl get pods --all-namespaces

.. note::

   Alternatively run this which will provide more information
   including pod ip addresses, but needs a wider terminal as a result:

     watch -d kubectl get pods --all-namespaces -o wide

Step 1: Deploy Kubernetes
=========================

.. note::

   This document recommends Kubernetes 1.6.2 or later.

.. warning::

   This documentation assumes a POD CIDR of 10.1.0.0/16 and a service CIDR of
   10.3.3.0/24.  Two rules must be followed when reading this guide.

   1. The service and pod cidr cannot overlap
   2. The address spaces cannot already be allocated by your organization

   If the POD and CIDR addresses overlap in this documentation with your organizations's
   IP address ranges, they may be changed.  Simply substitute anywhere these addresses
   are used with the custom cidrs you have chosen.


.. note::

   If you fail to turn off SELinux and firewalld, Kubernetes will fail.

Turn off SELinux::

    sudo setenforce 0
    sudo sed -i 's/enforcing/permissive/g' /etc/selinux/config

Turn off firewalld::

    sudo systemctl stop firewalld
    sudo systemctl disable firewalld

.. note::

   This operation configures the Kubernetes YUM repository.  This step only
   needs to be done once per server or VM.

.. warning::

   gpgcheck=0 is set below because the currently signed RPMs don't match
   the yum-key.gpg key distributed by Kubernetes.  YMMV.


CentOS
------

Write the Kubernetes repository file::

    sudo tee /etc/yum.repos.d/kubernetes.repo<<EOF
    [kubernetes]
    name=Kubernetes
    baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
    enabled=1
    gpgcheck=0
    repo_gpgcheck=1
    gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    EOF

Install Kubernetes 1.6.2 or later and other dependencies::

    sudo yum install -y docker ebtables kubeadm kubectl kubelet kubernetes-cni git gcc


Ubuntu
------
Write the kubernetes repository file::

    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo -E apt-key add -
    cat <<EOF > kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
    EOF

    sudo cp -aR kubernetes.list /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update

Install Kubernetes 1.6.2 or later and other dependencies::

    sudo apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni


Centos and Ubuntu
-----------------

Enable and start Docker::

    sudo systemctl enable docker
    sudo systemctl start docker

Ubuntu
------

Enable the proper CGROUP driver::

    CGROUP_DRIVER=$(sudo docker info | grep "Cgroup Driver" | awk '{print $3}')
    sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=$CGROUP_DRIVER |g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

Centos and Ubuntu
-----------------

Setup the DNS server with the service CIDR::

    sudo sed -i 's/10.96.0.10/10.3.3.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

.. note::

   Kubernetes uses x.x.x.10 as the DNS server.  The Kolla developers don't
   know precisely why this is the case, however, current speculation is that
   that 1..9 are reserved for future expansion of Kubernetes infrastructure
   services.

Reload the hand-modified service files::

    sudo systemctl daemon-reload

Stop kubelet if it is running::

    sudo systemctl stop kubelet

Enable and start docker and kubelet::

    sudo systemctl enable kubelet
    sudo systemctl start kubelet

Deploy Kubernetes with kubeadm::

    sudo kubeadm init --pod-network-cidr=10.1.0.0/16 --service-cidr=10.3.3.0/24

.. note::

   pod-network-cidr is a network private to Kubernetes that the PODs within
   Kubernetes communicate on. The service-cidr is where IP addresses for
   Kubernetes services are allocated.  There is no recommendation that
   the pod network should be /16 network in upstream documentation however, the
   Kolla developers have found through experience that each node consumes
   an entire /24 network, so this configuration would permit 255 Kubernetes nodes.

.. note::

   If the following issue occurs after running this command:

   `preflight] Some fatal errors occurred:
   /proc/sys/net/bridge/bridge-nf-call-iptables contents are not set
   to 1`

   There are two work-arounds:

   - Add `net.bridge.bridge-nf-call-ip6tables = 1` and
     `net.bridge.bridge-nf-call-iptables = 1` to
     ``/etc/sysctl.conf``
   - Type `sysctl -p` to apply the settings from /etc/sysctl.conf
   - Type `sysctl net.bridge.bridge-nf-call-ip[6]tables` to verify the
     values are set to 1.
   - Or alternatively Run with `--skip-preflight-checks`. This runs
     the risk of missing other issues that may be flagged.

Load the kubedm credentials into the system::

    mkdir -p $HOME/.kube
    sudo -H cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo -H chown $(id -u):$(id -g) $HOME/.kube/config

.. note::

   Until this step is done, the `watch terminal` will not return information.

The CNI driver is the networking driver that Kubernetes uses.  Kolla uses Canal
currently in the gate and tests with it hundreds of times per day via
extensive gating mechanisms.  Kolla recommends the use of Canal although other
CNI drivers may be used if they are properly configured.

Deploy the Canal CNI driver::

    curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/1.6/rbac.yaml -o rbac.yaml
    kubectl apply -f rbac.yaml

    curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/1.6/canal.yaml -o canal.yaml
    sed -i "s@192.168.0.0/16@10.1.0.0/16@" canal.yaml
    sed -i "s@10.96.232.136@10.3.3.100@" canal.yaml
    kubectl apply -f canal.yaml

Finally untaint the node (mark the master node as schedulable) so that
PODs can be scheduled to this AIO deployment::

    kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

.. note::

    Kubernetes must start completely before verification will function
    properly.

    In your `watch terminal`, confirm that Kubernetes has completed
    initialization by observing that the dns pod is in `3/3 Running`
    state. If you fail to wait, Step 2 will fail.

Step 2: Validate Kubernetes
===========================

After executing Step 2, a working Kubernetes deployment should be achieved.

Launch a busybox container::

    kubectl run -i -t $(uuidgen) --image=busybox --restart=Never

Verify DNS works properly by running below command within the busybox container::

    nslookup kubernetes

This should return a nslookup result without error::

    $ kubectl run -i -t $(uuidgen) --image=busybox --restart=Never
    Waiting for pod default/33c30c3b-8130-408a-b32f-83172bca19d0 to be running, status is Pending, pod ready: false

    # nslookup kubernetes
    Server:    10.3.3.10
    Address 1: 10.3.3.10 kube-dns.kube-system.svc.cluster.local

    Name:      kubernetes
    Address 1: 10.3.3.1 kubernetes.default.svc.cluster.local

.. warning::

   If nslookup kubernetes fails, kolla-kubernetes will not deploy correctly.
   If this occurs check that all preceding steps have been applied correctly, and that
   the range of IP addresses chosen make sense to your particular environment. Running
   in a VM can cause nested virtualization and or performance issues. If still stuck
   seek further assistance from the Kubernetes or Kolla communities.


Step 3: Deploying kolla-kubernetes
==================================

Override default RBAC settings::

    kubectl update -f <(cat <<EOF
    apiVersion: rbac.authorization.k8s.io/v1alpha1
    kind: ClusterRoleBinding
    metadata:
      name: cluster-admin
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: cluster-admin
    subjects:
    - kind: Group
      name: system:masters
    - kind: Group
      name: system:authenticated
    - kind: Group
      name: system:unauthenticated
    EOF
    )

Install and deploy Helm::

    curl -L https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
    chmod 700 get_helm.sh
    ./get_helm.sh
    helm init

.. note::
   In your `watch terminal` wait for the tiller pod to successfully
   come up.

Verify both the client and server version of Helm are consistent::

    helm version

Install repositories necessary to install packaging::

    sudo yum install -y epel-release ansible python-pip python-devel

.. note::

   You may find it helpful to create a directory to contain the files downloaded
   during the installation of kolla-kubernetes.  To do that::

       mkdir kolla-bringup
       cd kolla-bringup

Clone kolla-ansible::

    git clone http://github.com/openstack/kolla-ansible

Clone kolla-kubernetes::

    git clone http://github.com/openstack/kolla-kubernetes

Install kolla-ansible and kolla-kubernetes::

    sudo pip install -U kolla-ansible/ kolla-kubernetes/

Copy default Kolla configuration to /etc::

    sudo cp -aR /usr/share/kolla-ansible/etc/kolla /etc

Copy default kolla-kubernetes configuration to /etc::

    sudo cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc

Generate default passwords via SPRNG::

    sudo kolla-kubernetes-genpwd

Create a Kubernetes namespace to isolate this Kolla deployment::

    kubectl create namespace kolla

Label the AIO node as the compute and controller node::

    kubectl label node $(hostname) kolla_compute=true
    kubectl label node $(hostname) kolla_controller=true

.. warning:

    The kolla-kubernetes deliverable has two configuration files.  This is a little
    clunky and we know about the problem :)  We are working on getting all configuration
    into cloud.yaml. Until that is fixed the variable in globals.yml `kolla_install_type`
    must have the same contents as the variable in cloud.yaml `install_type`. In this
    document we use the setting `source` although `binary` could also be used.

Modify Kolla ``/etc/kolla/globals.yml`` configuration file::

    1. Set `network_interface` in `/etc/kolla/globals.yml` to the
       Management interface name. E.g: `eth0`.
    2. Set `neutron_external_interface` in `/etc/kolla/globals.yml` to the
       Neutron interface name. E.g: `eth1`. This is the external
       interface that Neutron will use.  It must not have an IP address
       assigned to it.

Add required configuration to the end of ``/etc/kolla/globals.yml``::

    cat <<EOF > add-to-globals.yml
    kolla_install_type: "source"
    tempest_image_alt_id: "{{ tempest_image_id }}"
    tempest_flavor_ref_alt_id: "{{ tempest_flavor_ref_id }}"

    neutron_plugin_agent: "openvswitch"
    api_interface_address: 0.0.0.0
    tunnel_interface_address: 0.0.0.0
    orchestration_engine: KUBERNETES
    memcached_servers: "memcached"
    keystone_admin_url: "http://keystone-admin:35357/v3"
    keystone_internal_url: "http://keystone-internal:5000/v3"
    keystone_public_url: "http://keystone-public:5000/v3"
    glance_registry_host: "glance-registry"
    neutron_host: "neutron"
    keystone_database_address: "mariadb"
    glance_database_address: "mariadb"
    nova_database_address: "mariadb"
    nova_api_database_address: "mariadb"
    neutron_database_address: "mariadb"
    cinder_database_address: "mariadb"
    ironic_database_address: "mariadb"
    placement_database_address: "mariadb"
    rabbitmq_servers: "rabbitmq"
    openstack_logging_debug: "True"
    enable_haproxy: "no"
    enable_heat: "no"
    enable_cinder: "yes"
    enable_cinder_backend_lvm: "yes"
    enable_cinder_backend_iscsi: "yes"
    enable_cinder_backend_rbd: "no"
    enable_ceph: "no"
    enable_elasticsearch: "no"
    enable_kibana: "no"
    glance_backend_ceph: "no"
    cinder_backend_ceph: "no"
    nova_backend_ceph: "no"
    EOF
    cat ./add-to-globals.yml | sudo tee -a /etc/kolla/globals.yml

For operators using virtualization for evaluation purposes please enable
QEMU libvirt functionality and enable a workaround for a bug in libvirt::

    sudo mkdir /etc/kolla/config
    sudo tee /etc/kolla/config/nova.conf<<EOF
    [libvirt]
    virt_type=qemu
    cpu_mode=none
    EOF

.. note::

   libvirt in RDO currently contains a bug that requires cpu_mode=none to be
   specified **only** for virtualized deployments.  For more information
   reference:
   https://www.redhat.com/archives/rdo-list/2016-December/msg00029.html

Generate the default configuration::

    sudo kolla-ansible genconfig

Generate the Kubernetes secrets and register them with Kubernetes::

    kolla-kubernetes/tools/secret-generator.py create

Create and register the Kolla config maps::

    kollakube res create configmap \
        mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
        nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
        glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
        neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
        openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
        nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
        nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
        cinder-scheduler cinder-volume iscsid tgtd keepalived \
        placement-api placement-api-haproxy

Enable resolv.conf workaround::

    kolla-kubernetes/tools/setup-resolv-conf.sh kolla

Build all Helm microcharts, service charts, and metacharts::

    kolla-kubernetes/tools/helm_build_all.sh .

Check that all Helm images have been built by verifying the number is > 150::

    ls | grep ".tgz" | wc -l

Create a local cloud.yml file for the deployment of the charts::

    cat <<EOF > cloud.yml
    global:
       kolla:
         all:
           docker_registry: docker.io
           image_tag: "4.0.0"
           kube_logger: false
           external_vip: "192.168.7.105"
           base_distro: "centos"
           install_type: "source"
           tunnel_interface: "docker0"
           resolve_conf_net_host_workaround: true
         keystone:
           all:
             admin_port_external: "true"
             dns_name: "192.168.7.105"
           public:
             all:
               port_external: "true"
         rabbitmq:
           all:
             cookie: 67
         glance:
           api:
             all:
               port_external: "true"
         cinder:
           api:
             all:
               port_external: "true"
           volume_lvm:
             all:
               element_name: cinder-volume
             daemonset:
               lvm_backends:
               - '192.168.7.105': 'cinder-volumes'
         ironic:
           conductor:
             daemonset:
               selector_key: "kolla_conductor"
         nova:
           placement_api:
             all:
               port_external: true
           novncproxy:
             all:
               port: 6080
               port_external: true
         openvwswitch:
           all:
             add_port: true
             ext_bridge_name: br-ex
             ext_interface_name: enp1s0f1
             setup_bridge: true
         horizon:
           all:
             port_external: true
    EOF

.. warning::

   This file is populated with several values that will need to
   be customized to your environment, this is explained below.

.. note::

   The placement api is enabled by default.  If you wish to disable the
   placement API to run Mitaka or Newton images, this can be done by
   setting the `variable global.kolla.nova.all.placement_api_enabled` to `false`
   in the cloud.yaml file.

.. note::
   The default docker registry is ``docker.io``. If you want to use local
   registry, modify the value of ``docker_registry`` to your local registry

.. note::

   The next operations are not a simple copy and paste as the rest of this
   document is structured.

   In `/etc/kolla/globals.yml` you assigned your Management interface
   name to `network_interface` (E.g. `eth0`) - we will refer to this
   as: `YOUR_NETWORK_INTERFACE_NAME_FROM_GLOBALS.YML`.

   Record the ip address assigned to
   `YOUR_NETWORK_INTERFACE_NAME_FROM_GLOBALS.YML`
   (E.g. `10.240.43.81`). We will refer to this as:
   `YOUR_NETWORK_INTERFACE_ADDRESS_FROM_GLOBALS.YML`.

   Also record the name of the `neutron_external_interface` from
   `/etc/kolla/globals.yml` (E.g. `eth1`). We will refer to this as:
   `YOUR_NEUTRON_INTERFACE_NAME_FROM_GLOBALS.YML`.

Replace all occurrences of `192.168.7.105` with
`YOUR_NETWORK_INTERFACE_ADDRESS_FROM_GLOBALS.YML`::

   sed -i "s@192.168.7.105@YOUR_NETWORK_INTERFACE_ADDRESS_FROM_GLOBALS.YML@g" ./cloud.yaml

.. note::

   This operation will have changed the values set in: `external_vip`, `dns_name` and
   `cinder-volumes` variables.

Replace `enp1s0f1` with `YOUR_NEUTRON_INTERFACE_NAME_FROM_GLOBALS.YML`::

   sed -i "s@enp1s0f1@YOUR_NEUTRON_INTERFACE_NAME_FROM_GLOBALS.YML@g" ./cloud.yaml

.. note::

   This operation will have changed the value set in:
   `ext_interface_name` variable.

Replace `docker0` with the management interface name (E.g. `eth0`) used for
connectivity between nodes in kubernetes cluster, in most cases it
is `YOUR_NETWORK_INTERFACE_NAME_FROM_GLOBALS.YML`::

   sed -i "s@docker0@YOUR_NETWORK_INTERFACE_NAME_FROM_GLOBALS.YML@g" ./cloud.yaml

.. note::

   This operation will have changed the value set in:
   `tunnel_interface` variable.

Start mariadb first and wait for it to enter into Running state::

    helm install --debug kolla-kubernetes/helm/service/mariadb --namespace kolla --name mariadb --values ./cloud.yaml

Start many of the remaining service level charts::

    helm install --debug kolla-kubernetes/helm/service/rabbitmq --namespace kolla --name rabbitmq --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/memcached --namespace kolla --name memcached --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/keystone --namespace kolla --name keystone --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/glance --namespace kolla --name glance --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/cinder-control --namespace kolla --name cinder-control --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/horizon --namespace kolla --name horizon --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/openvswitch --namespace kolla --name openvswitch --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/neutron --namespace kolla --name neutron --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/nova-control --namespace kolla --name nova-control --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/nova-compute --namespace kolla --name nova-compute --values ./cloud.yaml

Wait for nova-compute to enter into Running state before creating the cell0
database::

    helm install --debug kolla-kubernetes/helm/microservice/nova-cell0-create-db-job --namespace kolla --name nova-cell0-create-db-job --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-api-create-simple-cell-job --namespace kolla --name nova-api-create-simple-cell --values ./cloud.yaml

Deploy iSCSI support with Cinder LVM (Optional)

The Cinder LVM implementation requires a volume group to be set up. This can
either be a real physical volume or a loopback mounted file for development.
Use ``pvcreate`` and ``vgcreate`` to create the volume group.  For example
with the devices ``/dev/sdb`` and ``/dev/sdc``::

    <WARNING ALL DATA ON /dev/sdb and /dev/sdc will be LOST!>

    pvcreate /dev/sdb /dev/sdc
    vgcreate cinder-volumes /dev/sdb /dev/sdc

During development, it may be desirable to use file backed block storage. It
is possible to use a file and mount it as a block device via the loopback
system::

    mknod /dev/loop2 b 7 2
    dd if=/dev/zero of=/var/lib/cinder_data.img bs=1G count=20
    losetup /dev/loop2 /var/lib/cinder_data.img
    pvcreate /dev/loop2
    vgcreate cinder-volumes /dev/loop2

Note that in the event where iSCSI daemon is active on the host, there is a
need to perform the following steps before executing the cinder-volume-lvm Helm
chart to avoid the iscsd container from going into crash loops::

    sudo systemctl stop iscsid
    sudo systemctl stop iscsid.socket

Execute the cinder-volume-lvm Helm chart::

    helm install --debug kolla-kubernetes/helm/service/cinder-volume-lvm --namespace kolla --name cinder-volume-lvm --values ./cloud.yaml

In the `watch terminal` wait for all pods to enter into Running state.
If you didn't run watch in a different terminal, you can run it now::

    watch -d kubectl get pods --all-namespaces

Generate openrc file::

    kolla-kubernetes/tools/build_local_admin_keystonerc.sh ext
    source ~/keystonerc_admin

.. note::

   The ``ext`` option to create the keystonerc creates a keystonerc file
   that is compatible with this guide.

Install OpenStack clients::

    sudo pip install "python-openstackclient"
    sudo pip install "python-neutronclient"
    sudo pip install "python-cinderclient"

Bootstrap the cloud environment and create a VM as requested::

    kolla-ansible/tools/init-runonce

Create a floating IP address and add to the VM::

    openstack server add floating ip demo1 $(openstack floating ip create public1 -f value -c floating_ip_address)


Troubleshooting and Tear Down
=============================

TroubleShooting
---------------
.. note::

   This is just a list of popular commands the community has suggested
   they use a lot. This is by no means a comprehensive guide to
   debugging kubernetes or kolla.

Determine IP and port information::

  $ kubectl get svc -n kube-system
  NAME            CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
  canal-etcd      10.3.3.100   <none>        6666/TCP        16h
  kube-dns        10.3.3.10    <none>        53/UDP,53/TCP   16h
  tiller-deploy   10.3.3.7     <none>        44134/TCP       16h

  $ kubectl get svc -n kolla
  NAME                 CLUSTER-IP   EXTERNAL-IP    PORT(S)     AGE
  cinder-api           10.3.3.6     10.240.43.81   8776/TCP    15h
  glance-api           10.3.3.150   10.240.43.81   9292/TCP    15h
  glance-registry      10.3.3.119   <none>         9191/TCP    15h
  horizon              10.3.3.15    10.240.43.81   80/TCP      15h
  keystone-admin       10.3.3.253   10.240.43.81   35357/TCP   15h
  keystone-internal    10.3.3.155   <none>         5000/TCP    15h
  keystone-public      10.3.3.214   10.240.43.81   5000/TCP    15h
  mariadb              10.3.3.57    <none>         3306/TCP    15h
  memcached            10.3.3.180   <none>         11211/TCP   15h
  neutron-server       10.3.3.145   10.240.43.81   9696/TCP    15h
  nova-api             10.3.3.96    10.240.43.81   8774/TCP    15h
  nova-metadata        10.3.3.118   <none>         8775/TCP    15h
  nova-novncproxy      10.3.3.167   10.240.43.81   6080/TCP    15h
  nova-placement-api   10.3.3.192   10.240.43.81   8780/TCP    15h
  rabbitmq             10.3.3.158   <none>         5672/TCP    15h
  rabbitmq-mgmt        10.3.3.105   <none>         15672/TCP   15h

View all k8's namespaces::

  $ kubectl get namespaces
  NAME          STATUS    AGE
  default       Active    16h
  kolla         Active    15h
  kube-public   Active    16h
  kube-system   Active    16h

Kolla Describe a pod in full detail::

  kubectl describe pod ceph-admin -n kolla
  ...<lots of information>

View all deployed services::

  $ kubectl get deployment -n kube-system
  NAME            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
  kube-dns        1         1         1            1           20h
  tiller-deploy   1         1         1            1           20h

View configuration maps::

  $ kubectl get configmap -n kube-system
  NAME                                 DATA      AGE
  canal-config                         4         20h
  cinder-control.v1                    1         20h
  extension-apiserver-authentication   6         20h
  glance.v1                            1         20h
  horizon.v1                           1         20h
  keystone.v1                          1         20h
  kube-proxy                           1         20h
  mariadb.v1                           1         20h
  memcached.v1                         1         20h
  neutron.v1                           1         20h
  nova-api-create.v1                   1         19h
  nova-cell0-create-db-job.v1          1         19h
  nova-compute.v1                      1         19h
  nova-control.v1                      1         19h
  openvswitch.v1                       1         20h
  rabbitmq.v1                          1         20h

General Cluster information::

  $ kubectl cluster-info
  Kubernetes master is running at https://192.168.122.2:6443
  KubeDNS is running at https://192.168.122.2:6443/api/v1/proxy/namespaces/kube-system/services/kube-dns

View all jobs::

  $ kubectl get jobs --all-namespaces
  NAMESPACE     NAME                                              DESIRED   SUCCESSFUL   AGE
  kolla         cinder-create-db                                  1         1            20h
  kolla         cinder-create-keystone-endpoint-admin             1         1            20h
  kolla         cinder-create-keystone-endpoint-adminv2           1         1            20h
  kolla         cinder-create-keystone-endpoint-internal          1         1            20h
  kolla         cinder-create-keystone-endpoint-internalv2        1         1            20h
  kolla         cinder-create-keystone-endpoint-public            1         1            20h

View all deployments::

  $ kubectl get deployments --all-namespaces
  NAMESPACE     NAME              DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
  kolla         cinder-api        1         1         1            1           20h
  kolla         glance-api        1         1         1            1           20h
  kolla         glance-registry   1         1         1            1           20h
  kolla         horizon           1         1         1            1           20h
  kolla         keystone          1         1         1            1           20h
  kolla         memcached         1         1         1            1           20h
  kolla         neutron-server    1         1         1            1           20h
  kolla         nova-api          1         1         1            1           20h
  kolla         nova-novncproxy   1         1         1            1           20h
  kolla         placement-api     1         1         1            1           20h
  kube-system   kube-dns          1         1         1            1           20h
  kube-system   tiller-deploy     1         1         1            1           20h

View secrets::

  $ kubectl get secrets
  NAME                  TYPE                                  DATA      AGE
  default-token-3dzfp   kubernetes.io/service-account-token   3         20h

View docker images::

  $ sudo docker images
  REPOSITORY                                                TAG                 IMAGE ID            CREATED             SIZE
  gcr.io/kubernetes-helm/tiller                             v2.3.1              38527daf791d        7 days ago          56 MB
  quay.io/calico/cni                                        v1.6.2              db2dedf2181a        2 weeks ago         65.08 MB
  gcr.io/google_containers/kube-proxy-amd64                 v1.6.0              746d1460005f        3 weeks ago         109.2 MB
  ...

Tear Down
---------
.. warning::

   Some of these steps are dangerous.  Be warned.

To cleanup the database entry for a specific service such as nova::

    helm install --debug /opt/kolla-kubernetes/helm/service/nova-cleanup --namespace kolla --name nova-cleanup --values cloud.yaml

To delete a Helm release::

    helm delete mariadb --purge

To delete all Helm releases::

    helm delete mariadb --purge
    helm delete rabbitmq --purge
    helm delete memcached --purge
    helm delete keystone --purge
    helm delete glance --purge
    helm delete cinder-control --purge
    helm delete horizon --purge
    helm delete openvswitch --purge
    helm delete neutron --purge
    helm delete nova-control --purge
    helm delete nova-compute --purge
    helm delete nova-cell0-create-db-job --purge
    helm delete cinder-volume-lvm --purge

To clean up the host volumes between runs::

    sudo rm -rf /var/lib/kolla/volumes/*

To clean up Kubernetes and all docker containers entirely, run
this command, reboot, and run these commands again::

    sudo kubeadm reset

Using OpenStack
===============

If you were able to successfully reach the end of this guide and
`demo1` was successfully deployed, here is a fun list of things you
can do with your new cluster.

Access Horizon GUI
------------------
1. Determine Horizon `EXTERNAL IP` Address::

     $ kubectl get svc horizon --namespace=kolla
     NAME      CLUSTER-IP   EXTERNAL-IP     PORT(S)   AGE
     horizon   10.3.3.237   10.240.43.175   80/TCP    1d

2. Determine username and password from keystone::

     $ cat ~/keystonerc_admin | grep OS_USERNAME
     export OS_USERNAME=admin

     $ cat ~/keystonerc_admin | grep OS_PASSWORD
     export OS_PASSWORD=Sr6XMFXvbvxQCJ3Cib1xb0gZ3lOtBOD8FCxOcodU

3. Run a browser that has access to your network, and access Horizon
   GUI with the `EXTERNAL IP` from Step 1, using the credentials from Step 2.
