.. minikube_quickstart:

==========================================
Kolla Kubernetes Minikube Quickstart Guide
==========================================

Install MiniKube
================

Either from http://github.com/kubernetes/minikube
or if you are on linux with kvm, the following instructions:

Install minikube with kvm support

::

    curl -L -o docker-machine-driver-kvm \
      https://github.com/dhiltgen/docker-machine-kvm/releases/download/v0.7.0/docker-machine-driver-kvm
    chmod +x docker-machine-driver-kvm
    sudo mv docker-machine-driver-kvm /usr/local/bin/

    curl -L -o minikube \
      https://storage.googleapis.com/minikube/releases/v0.10.0/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/

    curl -Lo kubectl \
      http://storage.googleapis.com/kubernetes-release/release/v1.3.6/bin/linux/amd64/kubectl
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin

Start minikube and services
===========================

To start up a fresh kolla-kubernetes deployment, do the following.

::

    minikube start --vm-driver=kvm --memory=$((8*1024))

Enter Password if requested.

::

    minikube ssh

Wait for prompt...

::

    sudo su -
    mkdir -p /data/kolla
    dd if=/dev/zero of=/data/kolla/ceph-osd0.img bs=1 count=0 seek=3G
    LOOP=$(losetup -f)
    losetup $LOOP /data/kolla/ceph-osd0.img
    parted $LOOP mklabel gpt
    parted $LOOP mkpart 1 0% 512m
    parted $LOOP mkpart 2 513m 100%
    partprobe
    exit
    exit

Kubernetes web ui
=================

::

    minikube dashboard

Enter Password if requested.

::

    minikube ip

wait until you get a prompt...

Make note of the ip for future use.

Start a kolla-kubernetes environment

::

    kubectl run toolbox -it --image=kfox1111/kolla-kubernetes-toolbox:latest \
        --rm --restart=Never -- /bin/bash

wait until you get a prompt...

Run the following command, replacing <ip> with the ip you noted previously.

::

    ~/set_external_ip.sh <ip>

Run the folowing commands

::

    kubectl label node minikube kolla_controller=true
    kubectl label node minikube kolla_compute=true

    kubectl create namespace kolla
    tools/kolla-ansible genconfig
    ~/stash_config.sh push
    crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
    sed -i '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\n' /etc/kolla/ceph*/ceph.conf
    ../kolla-kubernetes/tools/fix-mitaka-config.py
    ../kolla-kubernetes/tools/secret-generator.py create
    ../kolla-kubernetes/tools/setup-resolv-conf.sh

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
             ceph-mon ceph-osd; \
    do
        kolla-kubernetes resource create configmap $x
    done

    kolla-kubernetes resource create bootstrap ceph-bootstrap-initial-mon
    watch kubectl get jobs --namespace=kolla

Wait for it...

::

    ../kolla-kubernetes/tools/setup-ceph-secrets.sh
    kolla-kubernetes resource delete bootstrap ceph-bootstrap-initial-mon
    kolla-kubernetes resource create pod ceph-mon
    watch kubectl get pods --namespace=kolla

Wait for it...

::

    kolla-kubernetes resource create pod ceph-bootstrap-osd
    watch kubectl get pods ceph-bootstrap-osd --show-all --namespace=kolla

Wait for it...

::

    kolla-kubernetes resource delete pod ceph-bootstrap-osd
    kolla-kubernetes resource create pod ceph-osd
    watch kubectl get pods ceph-osd --namespace=kolla

Wait for it...

::

    for x in images volumes vms; do
        kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash \
      -c "ceph osd pool create $x 64"
    done
    str="ceph auth get-or-create client.glance mon 'allow r' osd 'allow"
    str="$str class-read object_prefix rbd_children, allow rwx pool=images'"
    kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
      "$str" > /tmp/$$
    kubectl create secret generic ceph-client-glance-keyring --namespace=kolla\
        --from-file=ceph.client.glance.keyring=/tmp/$$
    str="ceph auth get-or-create client.cinder mon 'allow r' osd 'allow"
    str="$str class-read object_prefix rbd_children, allow rwx pool=volumes'"
    kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
      "$str" > /tmp/$$
    kubectl create secret generic ceph-client-cinder-keyring --namespace=kolla\
        --from-file=ceph.client.cinder.keyring=/tmp/$$
    str="ceph auth get-or-create client.nova mon 'allow r' osd 'allow "
    str="$str class-read object_prefix rbd_children, allow rwx pool=volumes, "
    str="$str allow rwx pool=vms, allow rwx pool=images'"
    kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
      "$str" > /tmp/$$
    kubectl create secret generic ceph-client-nova-keyring --namespace=kolla \
        --from-file=ceph.client.nova.keyring=/tmp/$$
    kubectl create secret generic nova-libvirt-bin --namespace=kolla \
        --from-file=data=<(awk '{if($1 == "key"){print $3}}' /tmp/$$ |
        tr -d '\n')
    kubectl exec ceph-osd -c main --namespace=kolla -- /bin/bash -c \
        "cat /etc/ceph/ceph.conf" > /tmp/$$
    kubectl create configmap ceph-conf --namespace=kolla \
        --from-file=ceph.conf=/tmp/$$
    rm -f /tmp/$$
    kolla-kubernetes resource create secret nova-libvirt

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
    watch kubectl get pods --namespace=kolla

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
             nova-novncproxy cinder-api cinder-scheduler \
             cinder-volume-ceph; \
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

    kolla-kubernetes resource create bootstrap openvswitch-set-external-ip
    kolla-kubernetes resource create pod nova-libvirt
    kolla-kubernetes resource create pod nova-compute 

    watch kubectl get jobs --namespace=kolla

wait for it...

::

    kolla-kubernetes resource delete bootstrap openvswitch-set-external-ip
    watch kubectl get pods --namespace=kolla

wait for it...

Services should be up now.

If you want to simply access the web gui, see section `Web Access`_ below.

To test things out

::

    ~/gen_keystone_admin.sh
    kubectl create -f ~/openstackcli.yaml --namespace=kolla
    watch kubectl get pod openstackcli --namespace=kolla

wait for it...

::

    kubectl exec -it openstackcli --namespace=kolla /bin/bash

Wait for prompt. Once you have one, you can run any openstack commands you wish.

for some tests:

::

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
    openstack volume create --size 1 test
    openstack ip floating add $FIP test
    openstack ip floating add $FIP2 test2
    openstack server add volume test test

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


NOTES
=====

petsets currently arn't deleted on delete...

If you want to push your config into a configmap so you can delete your
toolbox and get your configs back, you can do so like this

::

~/stash_config.sh push #push it to kubernetes
~/stash_config.sh pull #fetch config back from kubernetes

