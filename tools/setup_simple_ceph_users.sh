#!/bin/bash -e

str="ceph auth get-or-create client.glance mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=images'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-glance-keyring --namespace=kolla\
    --from-file=ceph.client.glance.keyring=/tmp/$$

str="ceph auth get-or-create client.cinder mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-cinder-keyring --namespace=kolla\
    --from-file=ceph.client.cinder.keyring=/tmp/$$
kubectl create secret generic nova-libvirt-bin --namespace=kolla \
    --from-file=data=<(awk '{if($1 == "key"){print $3}}' /tmp/$$ |
    tr -d '\n')

str="ceph auth get-or-create client.nova mon 'allow r' osd 'allow "
str="$str class-read object_prefix rbd_children, allow rwx pool=volumes, "
str="$str allow rwx pool=vms, allow rwx pool=images'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
kubectl create secret generic ceph-client-nova-keyring --namespace=kolla \
    --from-file=ceph.client.nova.keyring=/tmp/$$

str="ceph auth get-or-create client.kolla mon 'allow r' osd 'allow"
str="$str class-read object_prefix rbd_children, allow rwx pool=kollavolumes'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" | awk '{if($1 == "key"){print $3}}' > /tmp/$$
kubectl create secret generic ceph-kolla --namespace=kolla \
    --from-file=key=/tmp/$$
