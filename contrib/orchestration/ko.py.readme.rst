.. ko.py.readme.rst

==============================
"ko.py" - Kubernetes OpenStack
==============================

Purpose
=======

This is a tool to deploy OpenStack on a Kubernetes Cluster using Kolla images
and Kolla-Kubernetes on bare metal servers or virtual machines.

It sticks to the methods outlined in the kolla-kubernetes Bare Metal
Deployment Guide:

https://docs.openstack.org/developer/kolla-kubernetes/deployment-guide.html

Features
========
1. Supports both Centos and Ubuntu natively.

2. Requires just a VM with two NIC's, low congnitive overhead.

3. Simplicity to run: 'ko.py int1 int2'

4. Options to change the versions of all the tools, like helm, kubernetes etc.

5. Option to change the version of OpenStack as needed.

6. Easy on the eye output, with optional verbose mode for more information.

7. Contains a demo mode that walks the user through each step with additional
   information and instruction.

8. Verifies it's completeness by generating a VM in the OpenStack Cluster.

9. Leaves the user with a working OpenStack Cluster with all the basic
   services.

10. Lots of options to customize - even edit globals.yaml and cloud.yaml before
    deploying.

Host machine requirements
=========================

The host machine must satisfy the following minimum requirements:

- 2 network interfaces
- 8GB min, 16GB preferred RAM
- 40G min, 80GB preferred disk space
- 2 CPU's Min, 4 preferred CPU's
- Root access to the deployment host machine

Prerequisites
=============

Verify the state of network interfaces. If using a VM spawned on OpenStack as
the host machine, the state of the second interface will be DOWN on booting
the VM::

    ip addr show

Bring up the second network interface if it is down::

    ip link set ens4 up

However as this interface will be used for Neutron External, this Interface
should not have an IP Address. Verify this with::

    ip addr show


Mandatory Inputs
================

1. mgmt_int (network_interface)::
   Name of the interface to be used for management operations.

The `network_interface` variable is the interface to which Kolla binds API
services. For example, when starting Mariadb, it will bind to the IP on the
interface list in the ``network_interface`` variable.

2. neutron_int (neutron_external_interface)::
     Name of the interface to be used for Neutron operations.

The `neutron_external_interface` variable is the interface that will be used
for the external bridge in Neutron. Without this bridge the deployment instance
traffic will be unable to access the rest of the Internet.

To create two interfaces like this in Ubuntu, for example::

  Edit /etc/network/interfaces:

  # The primary network interface
  auto eth0
  iface eth0 inet dhcp

  # Neutron network interface (up but no ip address)
  auto eth1
  iface eth1 inet manual
  ifconfig eth1 up

TODO
====

1. Convert to using https://github.com/kubernetes-incubator/client-python
2. Add option to use a CNI other than canal
3. Note there are various todo's scattered inline as well.

Recomendations
==============
1. Due to the length the script can run for, recomend disabling sudo timeout::

     sudo visudo
     Add: 'Defaults    timestamp_timeout=-1'

2. Due to the length of time the script can run for, I recommend using nohup::

     E.g. nohup python -u k8s.py eth0 eth1

     Then in another window:

     tail -f nohup.out

OUTPUT
======

An example of ko.py running from beginning to end::

  ubuntu@ip-10-0-0-241:~/os$ ../k8s/ko.py ens3 ens4 -cn
  [sudo] password for ubuntu:
  [sudo] password for ubuntu:
  [sudo] password for ubuntu:


  *******************************************
  Kubernetes - Bring up a Kubernetes Cluster:
  *******************************************

  Linux info:        ('Ubuntu', '16.04', 'xenial')

  Networking:
  Management Int:  ens3
  Neutron Int:     ens4
  Management IP:   10.0.0.241
  VIP Keepalive:   10.0.0.56

  Versions:
  Docker version  :  1.12.6
  Openstack version: ocata(4.0.0)
  Helm version:      2.6.2
  K8s version:       1.8.2
  Ansible version:   2.2.0.0
  Jinja2 version:    2.8.1
  Base version:      centos


  (01/15) Kubernetes - Installing base tools
  (02/15) Kubernetes - Setup NTP
  (03/15) Kubernetes - Turn off firewall and ISCSID
  (04/15) Kubernetes - Creating Kubernetes repo, installing Kubernetes packages
  (05/15) Kubernetes - Start docker and setup the DNS server with the service CIDR
  (06/15) Kubernetes - Reload the hand-modified service files
  (07/15) Kubernetes - Enable and start kubelet
  (08/15) Kubernetes - Fix iptables to enable bridging
  (09/15) Kubernetes - Deploying Kubernetes with kubeadm (Slow!)
  You can now join any number of machines by running the following on each node as root:
  kubeadm join --token 5e76b0.5ac8cc93b3f53bbf 10.0.0.241:6443 --discovery-token-ca-cert-hash sha256:46665415bd9c77d9eb08af4d427b0925d8036278700894da412514cdd4c45195
  (10/15) Kubernetes - Load kubeadm credentials into the system
  Note "kubectl get pods --all-namespaces" should work now
  (11/15) Kubernetes - Wait for basic Kubernetes (6 pods) infrastructure
  *Running pod(s) status after 20 seconds 2:6*
  *Running pod(s) status after 50 seconds 3:6*
  *Running pod(s) status after 60 seconds 4:6*
  *Running pod(s) status after 70 seconds 5:6*
  *All pods 6/6 are started, continuing*
  (12/15) Kubernetes - Add API Server
  (13/15) Kubernetes - Deploy pod network SDN using Canal CNI
  Wait for all pods to be in Running state:
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (14/15) Kubernetes - Mark master node as schedulable by untainting the node
    (15/15) Kubernetes - Test 'nslookup kubernetes' - bring up test pod
  Wait for all pods to be in Running state:
    *01 pod(s) are not in Running state*
    *All pods are in Running state*


    ************************************
    Kubernetes Cluster is up and running
    ************************************

    **************************
    Kolla - install OpenStack:
    **************************

    (01/45) Kolla - Overide default RBAC settings
    (02/45) Kolla - Install and deploy Helm version 2.6.2 - Tiller pod
    Wait for all pods to be in Running state:
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (03/45) Kolla - Helm successfully installed
    (04/45) Kolla - Clone kolla-ansible
    (05/45) Kolla - Clone kolla-kubernetes
    (06/45) Kolla - Install kolla-ansible and kolla-kubernetes
    (07/45) Kolla - Copy default kolla-ansible configuration to /etc
    (08/45) Kolla - Copy default kolla-kubernetes configuration to /etc
    (09/45) Kolla - Setup Loopback LVM for Cinder (Slow!)
    (10/45) Kolla - Install Python Openstack Client
    (11/45) Kolla - Generate default passwords via SPRNG
    (12/45) Kolla - Create a Kubernetes namespace "kolla" to isolate this Kolla deployment
    (13/45) Kolla - Label Nodes:
    Label the AIO node as 'kolla_compute'
    Label the AIO node as 'kolla_controller'
    (14/45) Kolla - Modify global.yml to setup network_interface and neutron_interface
    (15/45) Kolla - Add default config to globals.yml
    (16/45) Kolla - Enable qemu
    (17/45) Kolla - Generate the default configuration
    (18/45) Kolla - Generate the Kubernetes secrets and register them with Kubernetes
    (19/45) Kolla - Create and register the Kolla config maps
    (20/45) Kolla - Build all Helm microcharts, service charts, and metacharts (Slow!)
    (21/45) Kolla - Verify number of helm images
    195 Helm images created
    (22/45) Kolla - Create a version 4 cloud.yaml
    (23/45) Kolla - Helm Install service chart: \--'openvswitch'--/
  Wait for all pods to be in Running state:
    *02 pod(s) are not in Running state*
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (24/45) Kolla - Helm Install service chart: \--'mariadb'--/
  Wait for all pods to be in Running state:
    *02 pod(s) are not in Running state*
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (25/45) Kolla - Helm Install service chart: \--'rabbitmq'--/
    (26/45) Kolla - Helm Install service chart: \--'memcached'--/
    (27/45) Kolla - Helm Install service chart: \--'keystone'--/
    (28/45) Kolla - Helm Install service chart: \--'glance'--/
    (29/45) Kolla - Helm Install service chart: \--'cinder-control'--/
    (30/45) Kolla - Helm Install service chart: \--'cinder-volume-lvm'--/
    (31/45) Kolla - Helm Install service chart: \--'horizon'--/
    (32/45) Kolla - Helm Install service chart: \--'neutron'--/
  Wait for all pods to be in Running state:
    *45 pod(s) are not in Running state*
    *44 pod(s) are not in Running state*
    *43 pod(s) are not in Running state*
    *42 pod(s) are not in Running state*
    *40 pod(s) are not in Running state*
    *39 pod(s) are not in Running state*
    *37 pod(s) are not in Running state*
    *35 pod(s) are not in Running state*
    *34 pod(s) are not in Running state*
    *31 pod(s) are not in Running state*
    *30 pod(s) are not in Running state*
    *29 pod(s) are not in Running state*
    *28 pod(s) are not in Running state*
    *27 pod(s) are not in Running state*
    *26 pod(s) are not in Running state*
    *25 pod(s) are not in Running state*
    *23 pod(s) are not in Running state*
    *20 pod(s) are not in Running state*
    *19 pod(s) are not in Running state*
    *16 pod(s) are not in Running state*
    *15 pod(s) are not in Running state*
    *14 pod(s) are not in Running state*
    *13 pod(s) are not in Running state*
    *11 pod(s) are not in Running state*
    *10 pod(s) are not in Running state*
    *08 pod(s) are not in Running state*
    *06 pod(s) are not in Running state*
    *05 pod(s) are not in Running state*
    *04 pod(s) are not in Running state*
    *03 pod(s) are not in Running state*
    *02 pod(s) are not in Running state*
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (33/45) Kolla - Helm Install service chart: \--'nova-control'--/
    (34/45) Kolla - Helm Install service chart: \--'nova-compute'--/
  Wait for all pods to be in Running state:
    *23 pod(s) are not in Running state*
    *22 pod(s) are not in Running state*
    *21 pod(s) are not in Running state*
    *19 pod(s) are not in Running state*
    *18 pod(s) are not in Running state*
    *17 pod(s) are not in Running state*
    *16 pod(s) are not in Running state*
    *15 pod(s) are not in Running state*
    *14 pod(s) are not in Running state*
    *13 pod(s) are not in Running state*
    *12 pod(s) are not in Running state*
    *11 pod(s) are not in Running state*
    *10 pod(s) are not in Running state*
    *09 pod(s) are not in Running state*
    *08 pod(s) are not in Running state*
    *01 pod(s) are not in Running state*
    *All pods are in Running state*
    (35/45) Kolla - Final Kolla Kubernetes OpenStack pods for namespace kube-system:
    NAME                                    READY     STATUS    RESTARTS   AGE
    canal-46w8r                             3/3       Running   0          14m
    etcd-ip-10-0-0-241                      1/1       Running   0          14m
    kube-apiserver-ip-10-0-0-241            1/1       Running   0          14m
    kube-controller-manager-ip-10-0-0-241   1/1       Running   0          14m
    kube-dns-545bc4bfd4-gnrlv               3/3       Running   0          15m
    kube-proxy-6c65v                        1/1       Running   0          15m
    kube-scheduler-ip-10-0-0-241            1/1       Running   0          14m
    tiller-deploy-cffb976df-thwlt           1/1       Running   0          13m
    (36/45) Kolla - Final Kolla Kubernetes OpenStack pods for namespace kolla:
    NAME                                      READY     STATUS    RESTARTS   AGE
    cinder-api-649bc7654d-5gf6g               3/3       Running   0          6m
    cinder-scheduler-0                        1/1       Running   0          6m
    cinder-volume-4n6rg                       1/1       Running   3          5m
    glance-api-7f5b759667-95g4v               1/1       Running   0          6m
    glance-registry-74cc4c977d-956l4          3/3       Running   0          6m
    horizon-7966fccff7-dbn2s                  1/1       Running   0          5m
    iscsid-xxmn4                              1/1       Running   0          5m
    keystone-55d7f5c7c-kjrg9                  1/1       Running   0          6m
    mariadb-0                                 1/1       Running   0          6m
    memcached-5b858fb696-4fmf6                2/2       Running   0          6m
    neutron-dhcp-agent-4xj76                  1/1       Running   0          5m
    neutron-l3-agent-network-9j978            1/1       Running   0          5m
    neutron-metadata-agent-network-nlpvd      1/1       Running   0          5m
    neutron-openvswitch-agent-network-8cc2x   1/1       Running   0          5m
    neutron-server-68d97c559f-xwwjl           3/3       Running   0          5m
    nova-api-69876b658f-pmf4f                 3/3       Running   0          2m
    nova-api-create-cell-sm6bj                1/1       Running   0          2m
    nova-compute-s9rbl                        1/1       Running   0          2m
    nova-conductor-0                          1/1       Running   0          2m
    nova-consoleauth-0                        1/1       Running   0          2m
    nova-libvirt-zjw6h                        1/1       Running   0          2m
    nova-novncproxy-58fb468d4b-4l57m          3/3       Running   0          2m
    nova-scheduler-0                          1/1       Running   0          2m
    openvswitch-ovsdb-network-j4gbm           1/1       Running   0          6m
    openvswitch-vswitchd-network-6q8lw        1/1       Running   0          6m
    placement-api-697b85cf9-6twdf             1/1       Running   0          2m
    rabbitmq-0                                1/1       Running   0          6m
    tgtd-wblfn                                1/1       Running   0          5m
    (37/45) Kolla - Create a keystone admin account and source in to it
    (38/45) Kolla - Allow Ingress by changing neutron rules
    (39/45) Kolla - Configure Neutron, pull images
    Enter passphrase (empty for no passphrase):
    Enter same passphrase again:
    (40/45) Kolla - Create a demo VM in our OpenStack cluster
    To create a demo image VM do:
    .  ~/keystonerc_admin; openstack server create --image cirros --flavor m1.tiny --key-name mykey --nic net-id=c7df4092-b88b-4596-bbad-6c1a2888ee82 test
  Kubernetes - Wait for VM demo1 to be in running state:
    *Kubernetes - VM demo1 is not Running yet - wait 15s*
    *Kubernetes - VM demo1 is not Running yet - wait 15s*
    *Kubernetes - VM demo1 is not Running yet - wait 15s*
    *Kubernetes - VM demo1 is Running*
    (41/45) Kolla - Create floating ip
    (42/45) Kolla - nova list to see floating IP and demo VM
    +--------------------------------------+-------+--------+------------+-------------+-------------------+
    | ID                                   | Name  | Status | Task State | Power State | Networks          |
    +--------------------------------------+-------+--------+------------+-------------+-------------------+
    | 1bd09c59-85a0-4d8f-9fc2-2949ca01192d | demo1 | ACTIVE | -          | Running     | public1=10.0.0.60 |
    +--------------------------------------+-------+--------+------------+-------------+-------------------+
    (43/45) Kolla - To Access Horizon:
    Point your browser to: 10.3.3.189
  OS_PASSWORD=oUfo1H4hSLxkJJbEmtieN7UN2sqwZfRGpaR8U6lW
  OS_USERNAME=admin


  **************************************************************************
  Successfully deployed Kolla-Kubernetes. OpenStack Cluster is ready for use
  **************************************************************************
