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

   This document was tested only against CentOS 7.3 Host OS and AIO
   environments.

Introduction
============

There are many ways to deploy Kubernetes.  This guide has been tested only with
kubeadm.  The documentation for Kubeadm is here:

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
    kubectl >= 1.6.1
    kubeadm >= 1.6.1
    kubelet >= 1.6.1
    kubernetes-cni >= 0.5.1

.. note::

   When working with Kubernetes it is considered a useful practice to open a
   unique terminal window and run the command that watches all kubernetes's
   processes.  This operation will show changes as they occur within
   Kubernetes and also shows the PODs IP addresses::

       watch -n 5 -c kubectl get pods --all-namespaces


Step 1: Deploy Kubernetes
=========================

.. note::

   This document recommends Kubernetes 1.6.1 or later.

.. warning::

   This documentation assumes a POD CIDR of 10.1.0.0/16 and a service CIDR of
   10.3.3.0/24.  Two rules must be followed when reading this guide.

   1. The service and pod cidr cannot overlap
   2. The address spaces cannot already be allocated by your organization

   If the POD and CIDR addresses overlap in this documentation with your organizations's
   IP address ranges, they may be changed.  Simply subtitute anywhere these addresses
   are used with the custom cidrs you hae chosen.


.. note::

   If you fail to turn off SELinux, kubernetes will fail.

Turn off SELinux::

    sudo setenforce 0
    sudo sed -i 's/enforcing/permissive/g' /etc/selinux/config

Turn off firewalld::

    sudo systemctl stop firewalld
    sudo systemctl disable firewalld

.. note::

   This operation configures the Kubernetes YUM repository.  This step only
   needs to be done one time.

.. warning::

   gpgcheck=0 is set below because the currently signed RPMs don't match
   the yum-key.gpg key distributed by Kubernetes.  YMMV.


CentOS
------

Write the kubernetes repository file::

    cat <<EOF > kubernetes.repo
    [kubernetes]
    name=Kubernetes
    baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
    enabled=1
    gpgcheck=0
    repo_gpgcheck=1
    gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    EOF
    sudo cp -a kubernetes.repo /etc/yum.repos.d

Install Kubernetes 1.6.1 or later::

    sudo yum install -y docker ebtables kubeadm kubectl kubelet kubernetes-cni

Ubuntu
------
write the kubernetes repository file::

    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo -E apt-key add -
    cat <<EOF > kubernetes.list
    deb http://apt.kubernetes.io/ kubernetes-xenial main
    EOF

    sudo cp -aR kubernetes.list /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update

Install Kubernetes 1.6.1 or later::

    sudo apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni

To enable the proper cgroup driver, start Docker and disable CRI::

    sudo systemctl enable docker
    sudo systemctl start docker
    CGROUP_DRIVER=$(sudo docker info | grep "Cgroup Driver" | awk '{print $3}')
    sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=$CGROUP_DRIVER --enable-cri=false |g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

Setup the DNS server with the service CIDR::

    sudo sed -i 's/10.96.0.10/10.3.3.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

.. note::

   Kubernetes uses x.x.x.10 as the DNS server.  The Kolla developers don't
   know precisely why this is the case, however, current speculation is that
   that 1..9 are reserved for future expansion of Kubernetes infrastructure
   services.

Then reload the hand-modified service files::

    sudo systemctl daemon-reload

Then stop kubelet if it is running::

    sudo systemctl stop kubelet

Then enable and start docker and kubelet::

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

Load the kubedm credentials into the system::

    mkdir -p $HOME/.kube
    sudo -H cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo -H chown $(id -u):$(id -g) $HOME/.kube/config

The CNI driver is the networking driver that Kubernetes uses.  Kolla uses canal
currently in the gate and tests with it hundreds of times per day via
extensive gating mechanisms.  Kolla recommends the use of canal although other
CNI drivers may be used if they are properly configured.

Deploy the canal CNI driver::

    curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/kubeadm/1.6/canal.yaml -o canal.yaml
    sed -i "s@192.168.0.0/16@10.1.0.0/16@" canal.yaml
    sed -i "s@10.96.232.136@10.3.3.100@" canal.yaml
    kubectl apply -f canal.yaml


Finally untaint the node so that PODs can be scheduled to this AIO deployment::

    kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

.. note::

    Kubernetes must start completely before verification will function
    properly. You will know kubernetes has completed initialization by
    checking using below command:

    $ kubectl get pods --all-namespaces | grep dns

    dns should be in 3/3 RUNNING. If you fail to wait, Step 2 will fail.

Step 2: Validate Kubernetes
===========================

After executing Step 2, a working Kubernetes deployment should be achieved.

Launch a busybox container::

    kubectl run -i -t $(uuidgen) --image=busybox --restart=Never

Verify DNS works properly by running below command within the busybox container::

    nslookup kubernetes

This should return a nslookup result without error::

    [sdake@kolla ~]$ kubectl run -i -t $(uuidgen) --image=busybox --restart=Never
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
    watch "kubectl get pods -n kube-system | grep tiller"

Verify both the client and server version of Helm are consistent::

    helm version

Install repositories necessary to install packaging::

    sudo yum install -y epel-release
    sudo yum install -y ansible python-pip python-devel

.. note::

   You may find it helpful to create a directory to contain the files downloaded
   during the installaiton of kolla-Kubernetes.  To do that::

       mkdir kolla-bringup
       cd kolla-bringup

Clone kolla-ansible::

    git clone http://github.com/openstack/kolla-ansible

Clone kolla-kubernetes::

    git clone http://github.com/openstack/kolla-kubernetes

Install kolla-kubernetes::

    sudo pip install -U kolla-ansible/ kolla-kubernetes/

Copy default kolla configuration to etc::

    sudo cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc

Copy default kolla-kubernetes configuration to /etc::

    sudo cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc

Generate default passwords via SPRNG::

    sudo kolla-kubernetes-genpwd

Create a kubernetes namespace to isolate this kolla deployment::

    kubectl create namespace kolla

Label the AIO node as the compute and controller node::

    kubectl label node $(hostname) kolla_compute=true
    kubectl label node $(hostname) kolla_controller=true

.. warning:

    The kolla-kubernetes deliverable has two configuraiton files.  This is a little
    clunky and we know about the problem :)  We are working on getting all configuraiton
    into cloud.yaml. Until that is fixed the variable in globals.yaml `kolla_install_type`
    must have the same contents as the variable in cloud.yaml `install_type`. In this
    document we use the setting `source` although `binary` could also be used.

Modify kolla configuration::

    set network_interface in /etc/kolla/globals.yaml to the management interface name.
    set neutron_external_interface in /etc/kolla/globals.yml to the Neutron interface name.
    This is the external interface that neutron will use.  It must not have an IP
    address assigned to it.

Add required configuration to the end of /etc/kolla/globals.yml::

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

    cat <<EOF > nova.conf
    [libvirt]
    virt_type=qemu
    cpu_mode=none
    EOF

    sudo mkdir /etc/kolla/config
    sudo cp -a nova.conf /etc/kolla/config

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

Build all helm microcharts, service charts, and metacharts::

    kolla-kubernetes/tools/helm_build_all.sh .

Check that all helm images have been built by verifying the number is > 150::

    ls | grep ".tgz" | wc -l

Create a cloud.yaml file for the deployment of the charts::

    global:
       kolla:
         all:
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

.. note::

   The placement api is enabled by default.  If you wish to disable the
   placement API to run Mitaka or Newton images, this can be done by
   setting the variable global.kolla.nova.all.placement_api_enabled to false
   in the cloud.yaml file.

.. note::

   The next operation is not a simple copy and paste as the rest of this
   document is structured.  You should determine your management interface
   which is the value of /etc/kolla/globals.yml and replace the contents
   of YOUR_NETWORK_INTERFACE_FROM_GLOBALS.YML in the following sed operation.

Replace all occurrences of 192.168.7.105 with your management interface nic (e.g. eth0)::

   sed -i "s@192.168.7.105@YOUR_NETWORK_INTERFACE_FROM_GLOBALS.YML@" ./cloud.yaml

Replace all occurrences of enp1s0f1 with your neutron interface name (e.g. eth1)::

   sed -i "s@enp1s0f1@YOUR_NEUTRON_NETWORK_INTERFACE_FROM_GLOBALS.YML@" ./cloud.yaml

.. note::

   Some of the variables in the cloud.yaml file that may need to be customized are:

   set 'external_vip': to the IP address of your management interface
   set 'dns_name' to the IP address of your management network
   set 'tunnel_interface': to the IP address of your management interface
   interface name used for connectivity between nodes in kubernetes
   cluster, in most of cases it matches the name of the kubernetes
   host management interface.  To determine this,
   ``grep network_interface /etc/kolla/globals.yml``.
   set ext_interface_name: to the interface name used for your Neutron network.

Start mariadb first and wait for it to enter the RUNNING state::

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

Wait for nova-compute the enter the running state before creating the cell0
database::

    helm install --debug kolla-kubernetes/helm/microservice/nova-cell0-create-db-job --namespace kolla --name nova-cell0-create-db-job --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-api-create-simple-cell-job --namespace kolla --name nova-api-create-simple-cell --values ./cloud.yaml

Deploy iSCSI support with Cinder LVM (Optional)

The Cinder LVM implementation requires a volume group to be set up. This can
either be a real physical volume or a loopback mounted file for development.
Use ``pvcreate`` and ``vgcreate`` to create the volume group.  For example
with the devices ``/dev/sdb`` and ``/dev/sdc``:

::

    <WARNING ALL DATA ON /dev/sdb and /dev/sdc will be LOST!>

    pvcreate /dev/sdb /dev/sdc
    vgcreate cinder-volumes /dev/sdb /dev/sdc

During development, it may be desirable to use file backed block storage. It
is possible to use a file and mount it as a block device via the loopback
system. ::

    mknod /dev/loop2 b 7 2
    dd if=/dev/zero of=/var/lib/cinder_data.img bs=1G count=20
    losetup /dev/loop2 /var/lib/cinder_data.img
    pvcreate /dev/loop2
    vgcreate cinder-volumes /dev/loop2

Note that in the event where iSCSI daemon is active on the host, there is a
need to perform the following steps before executing the cinder-volume-lvm helm
chart to avoid the iscsd container from going into crash loops:

::

    sudo systemctl stop iscsid
    sudo systemctl stop iscsid.socket

Execute the cinder-volume-lvm helm chart:

::

    helm install --debug kolla-kubernetes/helm/service/cinder-volume-lvm --namespace kolla --name cinder-volume-lvm --values ./cloud.yaml

Observe the previously running watch command in a different terminal. Wait
for all pods to to enter the running state.  If you didn't run watch in a
different terminal, you can run it now::

    watch -d -n 5 -c kubectl get pods --all-namespaces

Generate openrc file::

    kolla-kubernetes/tools/build_local_admin_keystonerc.sh ext
    source ~/keystonerc_admin

.. note::

   The ``ext`` option to create the keystonerc creates a keystonerc file
   that is compatible with this guide.

Install OpenStack Clients::

    sudo pip install "python-openstackclient"
    sudo pip install "python-neutronclient"
    sudo pip install "python-cinderclient"

Bootstrap the cloud envrionment and create a VM as requested::

    kolla-ansible/tools/init-runonce

Create a floating IP address and add to the VM::

    openstack server add floating ip demo1 $(openstack floating ip create public1 -f value -c floating_ip_address)


Troubleshooting
===============

.. warning::

   Some of these steps are dangerous.  Be warned.

To cleanup the database entry for a specific service such as nova:

    helm install --debug /opt/kolla-kubernetes//helm/service/nova-cleanup --namespace kolla --name nova-cleanup --values cloud.yaml

To delete a helm chart::

    helm delete --purge mariadb

To delete all helm charts::

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
