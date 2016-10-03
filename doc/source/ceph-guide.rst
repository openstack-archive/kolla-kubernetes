.. _ceph-guide:

====
Ceph
====

Overview
========

We are currently recommending that you deploy ceph using kolla-ansible or
ceph-deploy.

Install steps
=============

This list of instructions is currently incomplete.

completely remove the following option from /etc/kolla-kubernetes/kolla-kubernetes.yaml

::

    keyring: /etc/ceph/ceph.client.admin.keyring

set the user option in the storage_ceph to 'kolla' in /etc/kolla-kubernetes/kolla-kubernetes.yaml and
pool = kollavolumes

Upload ceph.conf and admin key generated from the external ceph while
orchestration_engine=ANSIBLE

::

    kubectl create configmap ceph-conf --namespace=kolla \
      --from-file=ceph.conf=/etc/kolla/ceph-osd/ceph.conf
    kubectl create secret generic ceph-client-admin-keyring --namespace=kolla\
      --from-file=data=/etc/kolla/ceph-osd/ceph.client.admin.keyring

Before any pv's are created, do the following

::

    kollakube res create pod ceph-rbd
    kollakube res create pod ceph-admin
    watch kubectl get pods --namespace=kolla

Wait for ceph-admin to come up.

Create a pool a user:

::
    #FIXME probably needs a pool per region name?
    str="ceph osd pool create kollavolumes 32"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
        "$str" > /tmp/$$
    str="ceph auth get-or-create client.kolla mon 'allow r' osd 'allow "
    str="$str class-read object_prefix rbd_children, allow rwx pool=kollavolumes"
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
        "$str" | awk '{if($1 == "key"){print $3}}' > /tmp/$$
    kubectl create secret generic ceph-kolla --namespace=kolla \
        --from-file=key=/tmp/$$
    rm -f /tmp/$$

Create disks for 'rabbitmq' and 'mariadb' like so

::

    cmd="rbd create --pool kollavolumes --image-feature layering --size 10240"
    cmd="$cmd mariadb; rbd map --pool kollavolumes mariadb; #format it and unmount/unmap..."
    kubectl exec -it ceph-admin -- /bin/bash -xec "$cmd"

Ceph managed by Kolla-Kubernetes
================================

It is very half baked, intended only for testing. Please don't store anything
you care about in it as we will guarantee it will loose your data.
