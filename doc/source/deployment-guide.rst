================================================
Bare Metal Deployment Guide for kolla-kubernetes
================================================

.. warning::

   This documentation is under construction and may not work perfectly.  If you
   run into trouble, please join #openstack-kolla and we learn together how to
   solve whatever issues you face.  Likely others in the community face the
   same issues.

.. note::

   This document was tested only against CentOS 7.3 Host OS and AIO
   environments.  As of Kubernetes 1.6, both DEB and RPM packages are broken
   from Kubernetes release repository.  As such, this guide only covers CentOS
   currently.  This guide will cover Ubuntu in a future revision.  You will also
   see mention of AIO in this guide.  As of Kubernetes 1.6, kubeadm join is
   broken.  The workaround used to build the RPM packages for CentOS for
   Kubernetes 1.5 do not enable a working kubeadm join operation either.  As a
   result, only AIO is covered in this document currently.

------------
Introduction
------------
There are many ways to deploy Kubernetes.  This guide has been tested only with
kubeadm.  The documentation for Kubeadm is here:

https://kubernetes.io/docs/

Here is a video shown at a Kubernetes specific meetup on February 15th, 2017:
https://youtu.be/rHCCUP2odd8

There are two steps to deploying kolla-kubernetes.  The first step involves
deploying Kubernetes.  The second step involves deploying Kolla that is
compatible with Kubernetes.

Dependencies::

    .. note::

       This document has lots of hard pin requirements.  The reason for these
       hard pins is because Kubernetes upstream released 1.6.0 without testing
       the generated RPMs. Please stick exactly to the versions specified in
       this guide.

    docker == 1.12.6
    helm >= 2.2.0
    kubectl == 1.5.4
    kubeadm == kubeadm-1.6.0-0.alpha.0.2074.a092d8e0f95f52.x86_64.rpm
    kubelet == 1.5.4
    kubernetes-cni == kubernetes-cni-0.3.0.1-0.07a8a2.x86_64.rpm

.. note::

   When working with Kubernetes it is considered a useful practice to open a
   unique terminal window and run the command that watches all kubernetes's
   processes.  This operation will show changes as they occur within
   Kubernetes and also shows the PODs IP addresses::

       watch -d -n 5 -c kubectl get pods -o wide --all-namespaces

-------------------------
Step 1: Deploy Kubernetes
-------------------------

.. note::

   This document recommends 1.5.4 as specified.  If you want to live on the
   bleeding edge and run Kubernetes 1.6.0, one of the co-authors of this
   document has contributed steps for Kubernetes 1.6.0.

.. warning::

   This operation configures the Kubernetes YUM repository.  This step only
   needs to be done one time.  At the time of the writing of this document
   upstream RPM repositories are broken as they are not gated.  To enable
   the Kubernetes repositories **once** they are fixed::

Install Kubernetes 1.5.4::

.. note::

    It is possible to build your own RPMs.  This is the technique used to
    produce the RPMs on fedorapeople.org::

        git clone https://github.com/kubernetes/release/tree/master/rpm
        git checkout efd57b86a69051b70cf08a73df0e1d672bc61272
        docker-build.sh

Install **unsigned** built RPMS that work for single node AIO::

    sudo yum install -y kubelet kubeadm kubectl kubernetes-cni
         https://fedorapeople.org/groups/kolla/kubeadm-1.6.0-0.alpha.0.2074.a092d8e0f95f52.x86_64.rpm \
         https://fedorapeople.org/groups/kolla/kubectl-1.5.4-0.x86_64.rpm \
         https://fedorapeople.org/groups/kolla/kubelet-1.5.4-0.x86_64.rpm \
         https://fedorapeople.org/groups/kolla/kubernetes-cni-0.3.0.1-0.07a8a2.x86_64.rpm

    sudo setenforce 0
    sudo systemctl enable docker && sudo systemctl start docker
    sudo systemctl enable kubelet && sudo systemctl start kubelet

There are four steps to deploy Kubernetes AIO:

Deploy Kubernetes with kubeadm::

    sudo kubeadm init --pod-network-cidr=10.1.0.0/16 --service-cidr=10.3.0.0/16

.. note::

   pod-network-cidr is a network private to Kubernetes that the PODs within
   Kubernetes communicate on. The service-cidr is ?? (what?)  There is no
   recommendation that these should be /16 networks in upstream documentation
   however, the Kolla developers have found through experience that each
   node consumes an entire /24 network, so this configuration would
   permit 255 Kubernetes nodes.


By default kubeadm does not set the kubelet DNS service IP.  The kubeadm
tool should set this value in systemd when --service-cidr is specified, but
it does not.  To set it properly run these commands:

Setup the DNS server with the service CIDR::

    sudo sed -i 's/10.96.0.10/10.3.0.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sudo systemctl daemon-reload kubelet
    sudo systemctl stop kubelet
    sudo systemctl start kubelet

.. note::

   Kubernetes uses x.x.x.10 as the DNS server.  The Kolla developers don't
   know precisely why this is the case, however, current speculation is that
   that 1..9 are reserved for future expansion of Kubernetes infrastructure
   services.  These instruction change the default that kubeadm uses which
   is incorrect for many environments to a default that should work on
   virtually any system.

The CNI driver is the networking driver that Kubernetes uses.  Kolla uses canal
exclusively in the gate and tests with it hundreds of times per day via
extensive gating mechanisms.  Kolla recommends the use of canal although other
CNI drivers may be used easily if they are properly configured.

Deploy a CNI driver::

    curl -L https://raw.githubusercontent.com/projectcalico/canal/7deb07cda04147ab49115f437151705c747d0374/k8s-install/kubeadm/canal.yaml -o canal.yaml

    sed -i "s@192.168.0.0/16@10.0.1.0/16@" canal.yaml
    sed -i "s@10.96.232.136@10.3.1.100@" canal.yaml
    kubectl apply -f canal.yaml

.. note::

   The above operation downloads a version of Canal that works.  Canal in
   master is recently broken for Kubernetes 1.5.0+.  This operation further
   sets the pod network cidr and the service network host.

.. warning::

   kubernetes 1.6.0 has confirmed defects wihch make it unstable at this time.
   We really recommend using 1.5.4.  If you wish to proceed with a 1.6.0 install
   the instructions are as follows:

Finally taint the node so that PODs can be scheduled to this AIO deployment::

    kubectl taint nodes --all dedicated-

(Bleeding Edge) Install Kubernetes 1.6.0::

In a terminal window watch all pods to make sure they enter a RUNNING state
without restarts::

    watch -d -n 5 -c kubectl get pods --all-namespaces

In a different terminal window run these operations:

    cat <<EOF > kubernetes.repo
    [kubernetes]
    name=Kubernetes
    baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
    enabled=1
    gpgcheck=1
    repo_gpgcheck=1
    gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    EOF
    sudo cp -a kubernetes.repo /etc/yum.repos.d

    sudo setenforce 0
    sudo yum install -y docker kubeadm-1.6.0-0.x86_64 kubelet kubectl kubernetes-cni ebtables iproute

Apply workarounds for various forms of broken Kubernetes packaging::

    sed -i 's|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--cgroup-driver=systemd --enable-cri=false |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sed -i 's|KUBELET_NETWORK_ARGS=.*|KUBELET_NETWORK_ARGS=" |g' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    systemctl enable docker && sudo systemctl start docker
    systemctl enable kubelet && sudo systemctl start kubelet
    systemctl daemon-reload

    kubeadm init --pod-network-cidr=10.1.0.0/16 --service-cidr=10.3.0.0/16

    echo "- --insecure-port=8880" >> /etc/kubernetes/manifestws/kube-apiserver.yaml
    echo "- --insecure-bind-address=0.0.0.0" >> /etc/kubernetes/manifestws/kube-apiserver.yaml

Deploy the canal CNI driver::

    sed -i 's/10.96.0.10/10.3.0.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    systemctl daemon-reload
    systemctl stop kubelet
    systemctl start kubelet

    curl -L https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/kubeadm/1.6/canal.yaml -o canal.yaml

    sed -i "s@192.168.0.0/16@10.0.1.0/16@" canal.yaml
    sed -i "s@10.96.232.136@10.3.1.100@" canal.yaml
    kubectl apply -f canal.yaml

Finally taint the node so that PODs can be scheduled to this AIO deployment::

    kubectl taint nodes --all dedicated-

---------------------------
Step 2: Validate Kubernetes
---------------------------
After executing Step 2, a working Kubernetes deployment should be achieved.

Launch a busybox container::

    kubectl run -i -t $(uuidgen) --image=busybox --restart=Never

Verify DNS works properly by running within the container::

    nslookup kubernetes

This should return a nslookup result without error::

    [sdake@kolla ~]$ kubectl run -i -t $(uuidgen) --image=busybox --restart=Never
    Waiting for pod default/33c30c3b-8130-408a-b32f-83172bca19d0 to be running, status is Pending, pod ready: false
    # nslookup kubernetes
    Server:    10.3.0.10
    Address 1: 10.3.0.10 kube-dns.kube-system.svc.cluster.local

    Name:      kubernetes
    Address 1: 10.3.0.1 kubernetes.default.svc.cluster.local

.. note::

   If nslookup kubernetes fails, kolla-kubernetes will not deploy correctly.
   If this occurs check that all preceding steps have been applied correctly, and that
   the range of iP addresses chosen make sense to your particular environment. Running
   in a VM can cause nested virtualization and or performance issues. If still stuck
   seek further assistance from the Kubernetes or Kolla communities.

----------------------------------
Step 3: Deploying kolla-kubernetes
----------------------------------

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

    # apply a cherrypick that fixes kollakube tool
    cd kolla-kubernetes
    git fetch git://git.openstack.org/openstack/kolla-kubernetes refs/changes/40/439740/19 && git cherry-pick FETCH_HEAD
    cd ..

Apply a temporary workaround for 4.0.0 placement API::

    cd kolla-ansible
    git am ../kolla-kubernetes/tools/patches/0001*
    cd ..

Install kolla-kubernetes::

    sudo pip install -U kolla-ansible/ kolla-kubernetes/

Copy default kolla configuration to etc::

    sudo cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc

Copy default kolla-kubernetes configuration to /etc::

    sudo cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc
    git am ../kolla-kubernetes/tools/patches/0001*
    cd ..

Install kolla-kubernetes::

    sudo pip install -U kolla-ansible/ kolla-kubernetes/

Copy default kolla configuration to etc::

    sudo cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc

Copy default kolla-kubernetes configuration to /etc::

    sudo cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc

Generate default passwords via SPRNG::

    sudo kolla-genpwd

Create a kubernetes namespace to isolate this kolla deployment::

    kubectl create namespace kolla

Label the AIO node as the compute and controller node::

    kubectl label node $(hostname) kolla_compute=true
    kubectl label node $(hostname) kolla_controller=true

Modify kolla configuration::

    set network_interface in /etc/kolla/globals.yaml to the management interface name.
    set neutron_external_interface in /etc/kolla/globals.yml to the Neutron interface name.

Add required configuration to the end of /etc/kolla/globals.yml::

    cat <<EOF > add-to-globals.yml
    tempest_image_alt_id: "{{ tempest_image_id }}"
    tempest_flavor_ref_alt_id: "{{ tempest_flavor_ref_id }}"

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
    sudo cat ./add-to-globals.yml >> /etc/kolla/globals.yml

For operators using Virtualization for evaluation purposes please enable
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

    sudo kolla-kubernetes/tools/secret-generator.py create

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

    sudo kolla-kubernetes/tools/setup-resolv-conf.sh kolla

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
           external_vip: "192.168.7.101"
           base_distro: "centos"
           install_type: "source"
           tunnel_interface: "docker0"
           resolve_conf_net_host_workaround: true
         keystone:
           all:
             admin_port_external: "true"
             dns_name: "192.168.7.101"
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
                 - 192.168.7.101: cinder-volumes
         ironic:
           conductor:
             daemonset:
               selector_key: "kolla_conductor"
         nova:
           placement_api:
            all:
              node_port: 8780
              node_port_enabled: false
              port: 8780
              port_external: true
         horizon:
           all:
             port_external: true


.. note::

   set 'external_vip': your external ip address
   set 'ext_interface_name': name of the interface or bridge which will be used by neutron's provider interface
   set 'ext_bridge_name': name of the bridge you want neutron to use as an external bridge.  By default it should be br-ex.
   set 'tunnel_interface': interface name used for connectivity between nodes in kubernetes cluster, in most of cases it matches the name of the kubernetes host management interface

Start all service level charts::

    helm install --debug kolla-kubernetes/helm/service/mariadb --namespace kolla --name mariadb --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/rabbitmq --namespace kolla --name rabbitmq --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/memcached --namespace kolla --name memcached --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/keystone --namespace kolla --name keystone --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/glance --namespace kolla --name glance --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/cinder-control --namespace kolla --name cinder-control --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/cinder-volume-lvm-daemonset --namespace kolla --name cinder-volume --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/horizon --namespace kolla --name horizon --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/openvswitch --namespace kolla --name openvswitch --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/neutron --namespace kolla --name neutron --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/nova-control --namespace kolla --name nova-control --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/service/nova-compute --namespace kolla --name nova-compute --values ./cloud.yaml

Start some 4.0.0 charts required that are not yet in service charts::

    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-deployment --namespace kolla --name nova-placement-deployment --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-create-keystone-user-job --namespace kolla --name nova-placement-create-keystone-user-job --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-create-keystone-service-job --namespace kolla --name nova-placement-create-keystone-service-job --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-svc --namespace kolla --name nova-placement-svc --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-create-keystone-endpoint-internal-job --namespace kolla --name nova-placement-create-keystone-endpoint-internal --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-create-keystone-endpoint-admin-job --namespace kolla --name nova-placement-create-keystone-endpoint-admin --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-placement-create-keystone-endpoint-public-job --namespace kolla --name nova-placement-create-keystone-endpoint-public --values ./cloud.yaml

Wait for nova-compute the enter the running state before creating the cell0
database::

    helm install --debug kolla-kubernetes/helm/microservice/nova-cell0-create-db-job --namespace kolla --name nova-cell0-create-db-job --values ./cloud.yaml
    helm install --debug kolla-kubernetes/helm/microservice/nova-api-create-simple-cell-job --namespace kolla --name nova-api-create-simple-cell --values ./cloud.yaml

.. note::

   The main editor of this document (sdake) is unclear if the cell0 creation
   should happen before or after the placement API creaiton.

Observe the previously running watch command in a different terminal.  Wait
for all pods to to enter the running state.  If you didn't run watch in a
different terminal, you can run it now::

    watch kubectl get pods -n kolla

Generate openrc file::

    sudo kolla-ansible post-deploy
    sudo kolla-kubernetes/tools/build_local_admin_keystonerc.sh ext
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

    openstack server add floating ip demo1 $(openstack floating ip create public1)

Troubleshooting
---------------

.. note::

   Some of these steps are dangerous.  Be warned.

To cleanup the database entry for a specific service such as nova:

    helm install --debug /opt/kolla-kubernetes//helm/service/nova-cleanup --namespace kolla --name nova-cleanup --values cloud.yaml

To delete a helm chart::

    helm delete --purge mariadb

To delete all helm harts::

    helm delete mariadb --purge
    helm delete rabbitmq --purge
    helm delete memcached --purge
    helm delete keystone --purge
    helm delete glance --purge
    helm delete cinder-control --purge
    helm delete cinder-volume-lvm-daemonset --purge
    helm delete horizon --purge
    helm delete openvswitch --purge
    helm delete neutron --purge
    helm delete nova-control --purge
    helm delete nova-compute --purge
    helm delete nova-cell0-create-db-job --purge
    helm delete nova-placement-deployment --purge
    helm delete cinder-volume --purge

To clean up the host volumes::

    sudo rm -rf /var/lib/kolla/volumes/*

To clean up Kubernetes and all docker containers entirely, run
these commands, reboot, and run these commands again::

    #!/bin/bash
    systemctl stop kubelet.service
    docker ps -a --format '{{.ID}}' | xargs docker stop
    docker ps -a --format '{{.ID}}' | xargs docker rm -f
    systemctl stop docker.service
    systemctl stop kubelet.service
    rm -rf /etc/kubernetes
    rm -rf ~/.helm/
    rm -rf ~/.kube/
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/etcd
    rm -rf /var/run/calico/
    rm -rf /var/etcd/
    rm -rf /etc/cni/
    rm -rf /run/kubernetes
    rm -rf /var/lib/kubelet
    rm -rf /opt/cni
    systemctl start docker.service
    systemctl start kubelet.service
