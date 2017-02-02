#!/bin/bash -xe

if [ "x$1" != "x--yes-i-really-really-mean-it" ]; then
    echo This command is destructive. You must pass the
    echo --yes-i-really-really-mean-it if you are sure.
    exit -1
fi

if [ "x$2" == "x2" ]; then
    RBD_ARGS=""
else
    RBD_ARGS="--image-feature layering"
fi

#FIXME may need different flags for testing jewel
str="timeout 240s rbd create kollavolumes/mariadb $RBD_ARGS --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="timeout 60s rbd create kollavolumes/rabbitmq $RBD_ARGS --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="timeout 60s rbd create kollavolumes/helm-repo $RBD_ARGS --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="timeout 60s rbd create kollavolumes/glance $RBD_ARGS --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"

for volume in mariadb rabbitmq glance helm-repo; do
    str='DEV=$(rbd map --pool kollavolumes '$volume'); mkfs.xfs $DEV;'
    str="$str rbd unmap "'$DEV;'
    timeout 60s kubectl exec ceph-admin -c main --namespace=kolla -- \
        /bin/bash -c "$str"
done
