#!/bin/bash -xe

if [ "x$1" != "x--yes-i-really-really-mean-it" ]; then
    echo This command is distructive. You must pass the
    echo --yes-i-really-really-mean-it if you are sure.
    exit -1
fi

#FIXME may need different flags for testing jewel
str="timeout 240s rbd create kollavolumes/mariadb --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="timeout 60s rbd create kollavolumes/rabbitmq --size 1024"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"

for volume in mariadb rabbitmq; do
    str='DEV=$(rbd map --pool kollavolumes '$volume'); mkfs.xfs $DEV;'
    str="$str rbd unmap "'$DEV;'
    timeout 60s kubectl exec ceph-admin -c main --namespace=kolla -- \
        /bin/bash -c "$str"
done
