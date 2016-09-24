.. quickstart:

=================================
Kolla Kubernetes Quickstart Guide
=================================

Configure Kolla-Kubernetes
==========================

Edit the file ``/etc/kolla/globals.yml`` to add these settings which
are specific to kolla-kubernetes:

::

    # Kolla-kubernetes custom configuration
    orchestration_engine: "KUBERNETES"
    api_interface_address: "0.0.0.0"
    memcached_servers: "memcached"
    keystone_database_address: "mariadb"
    keystone_admin_url: "http://keystone-admin:35357/v3"
    keystone_internal_url: "http://keystone-public:5000/v3"
    keystone_public_url: "http://keystone-public:5000/v3"
    glance_registry_host: "glance"

Then, generate the Kolla configuration files:

::

    # Generate Kolla Configuration Files
    pushd kolla
    sudo ./tools/generate_passwords.py
    sudo ./tools/kolla-ansible genconfig
    popd

If using a virt setup, set nova to use qemu unless your environment has
nested virt capabilities enabled::

    crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu

Labeling Nodes
==============

Your cluster needs to have at least one node labeled with each of the
following labels::

    kolla_compute=true
    kolla_controller=true

Label you current node::
    ALLINONENODE=$(hostname)
    kubectl label node $ALLINONENODE kolla_compute=true
    kubectl label node $ALLINONENODE kolla_controller=true

Alternately, you can override the default labeling used in the
kolla-kubernetes.yml file. It is also possible to target specific
services to specific pools of nodes with this mechanism.

Generating Kubernetes Secrets
=============================

Create the kubernetes namespace. By default it is 'kolla'.

::
    kubectl create namespace 'kolla'

Generating Kubernetes Secrets
=============================

Before using this script, you MUST generate passwords by using
generate_passwords.py (comes with kolla distribution), if there is no
password.yml at /etc/kolla, the script will generate an error.
Script accepts 1 parameter: "create" or "delete".

::

    # To create Secrets for all services in passwords.yml run:
    secret-generator.py create
    # To delete Secrets for all services in passwords.yml run:
    secret-generator.py delete

Resolv.conf Workaround
======================

Kubernetes uses service discovery for all pods including the net=host pods.
In the net=host pods, resolv.conf doesn't point at kube-dns. Kolla-kubernetes
provides a workaround by creating a configmap called resolv-conf with a
resolv.conf from a non net=host pod so that dns properly resolves.

Create the resolv.conf configmap::

  ./tools/setup-resolv-conf.sh

Running Kolla-Kubernetes
========================

The following commands will walk through the deployment of the OpenStack
services.  There will be pauses in between commands to sure they completed.
In the future, this will be handled as a workflow::

    for x in mariadb keystone horizon rabbitmq memcached nova-api \
             nova-conductor nova-scheduler glance-api-haproxy \
             glance-registry-haproxy glance-api glance-registry \
             neutron-server neutron-dhcp-agent neutron-l3-agent \
             neutron-metadata-agent neutron-openvswitch-agent \
             openvswitch-db-server openvswitch-vswitchd nova-libvirt \
             nova-compute nova-consoleauth nova-novncproxy \
             nova-novncproxy-haproxy neutron-server-haproxy \
             nova-api-haproxy cinder-api cinder-api-haproxy \
             cinder-backup cinder-scheduler cinder-volume \
             tgtd iscsid; \
    do
        kolla-kubernetes resource create configmap $x
    done
    for x in mariadb rabbitmq glance; do
        kolla-kubernetes resource create pv $x
        kolla-kubernetes resource create pvc $x
    done
    for x in mariadb memcached keystone-admin keystone-public rabbitmq \
             rabbitmq-management nova-api glance-api glance-registry \
             neutron-server nova-metadata nova-novncproxy horizon \
             cinder-api; \
    do
        kolla-kubernetes resource create svc $x
    done

    for x in mariadb-bootstrap rabbitmq-bootstrap; do
        kolla-kubernetes resource create bootstrap $x
    done
    watch kubectl get jobs --namespace kolla

wait for it....

::

    for x in mariadb-bootstrap rabbitmq-bootstrap; do
        kolla-kubernetes resource delete bootstrap $x
    done
    for x in mariadb memcached rabbitmq; do
        kolla-kubernetes resource create pod $x
    done
    watch kubectl get pods --namespace kolla

wait for it...

::

    for x in keystone-create-db keystone-endpoints keystone-manage-db; do
        kolla-kubernetes resource create bootstrap $x
    done
    watch kubectl get jobs --namespace kolla

wait for it...

::

    for x in keystone-create-db keystone-endpoints keystone-manage-db; do
        kolla-kubernetes resource delete bootstrap $x
    done
    kolla-kubernetes resource create pod keystone
    watch kolla-kubernetes resource status pod keystone

wait for it...

::

    for x in glance-create-db glance-endpoints glance-manage-db \
             nova-create-api-db nova-create-endpoints nova-create-db \
             neutron-create-db neutron-endpoints neutron-manage-db \
             cinder-create-db cinder-create-endpoints cinder-manage-db; \
    do
        kolla-kubernetes resource create bootstrap $x
    done
    watch kubectl get jobs --namespace=kolla

wait for it...

::

    for x in glance-create-db glance-endpoints glance-manage-db \
             nova-create-api-db nova-create-endpoints nova-create-db \
             neutron-create-db neutron-endpoints neutron-manage-db \
             cinder-create-db cinder-create-endpoints cinder-manage-db; \
    do
         kolla-kubernetes resource delete bootstrap $x
    done
    for x in nova-api nova-conductor nova-scheduler glance-api \
             glance-registry neutron-server horizon nova-consoleauth \
             nova-novncproxy cinder-api cinder-scheduler; \
    do
        kolla-kubernetes resource create pod $x
    done
    watch kubectl get pods --namespace=kolla

wait for it...

::

    for x in openvswitch-ovsdb-network openvswitch-vswitchd-network \
             neutron-openvswitch-agent-network neutron-dhcp-agent \
             neutron-metadata-agent-network neutron-l3-agent-network; \
    do
        kolla-kubernetes resource create pod $x
    done

    kolla-kubernetes resource create pod nova-libvirt
    kolla-kubernetes resource create pod nova-compute
    watch kubectl get pods --namespace=kolla

wait for it...

Services should be up now.

If you want to simply access the web gui, see section `Web Access`_ below.

Generate Credentials
====================

This will be automated by an created an "operator pod" in the future.
Credentials can be generated by hand by looking in ``/etc/kolla/globals.yml``
and filling in these variables::

  export OS_PROJECT_DOMAIN_ID=default
  export OS_USER_DOMAIN_ID=default
  export OS_PROJECT_NAME=admin
  export OS_USERNAME=admin
  export OS_PASSWORD=<keystone_admin_password>
  export OS_AUTH_URL=http://<kolla_internal_fqdn>:<keystone_admin_port>
  export OS_IDENTITY_API_VERSION=3

Testing OpenStack
================

After sourcing your credentials start using the services::

    openstack catalog list

    curl -o cirros.qcow2 \
        http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
    openstack image create --file cirros.qcow2 --disk-format qcow2 \
         --container-format bare 'CirrOS'

    neutron net-create --provider:physical_network=physnet1 \
        --provider:network_type=flat external
    neutron net-update --router:external=True external
    neutron subnet-create --gateway 172.18.0.1 --disable-dhcp \
        --allocation-pool start=172.18.0.65,end=172.18.0.254 \
        --name external external 172.18.0.0/24
    neutron router-create admin
    neutron router-gateway-set admin external

    neutron net-create admin
    neutron subnet-create --gateway=172.18.1.1 \
        --allocation-pool start=172.18.1.65,end=172.18.1.254 \
        --name admin admin 172.18.1.0/24
    neutron router-interface-add admin admin
    neutron security-group-rule-create --protocol icmp \
        --direction ingress default
    neutron security-group-rule-create --protocol tcp \
        --port-range-min 22 --port-range-max 22 \
        --direction ingress default

    openstack server create --flavor=m1.tiny --image CirrOS \
         --nic net-id=admin test
    openstack server create --flavor=m1.tiny --image CirrOS \
         --nic net-id=admin test2
    FIP=$(openstack ip floating create external -f value -c ip)
    FIP2=$(openstack ip floating create external -f value -c ip)
    openstack ip floating add $FIP test
    openstack ip floating add $FIP2 test2

    watch openstack server list

wait for it...

::

    ssh cirros@$FIP curl 169.254.169.254

.. _`Web Access`:

Web Access
==========
If you want to access the horizon website, fetch the admin password from
within the toolbox like:

::
    grep keystone_admin /etc/kolla/passwords.yml

And paste in the ip address you noted earlier from 'minikube ip' into your
web browser. The username is 'admin'.


.. NOTE:: petsets currently arn't deleted on delete. The resources for it will
have to be cleaned up by hand.
