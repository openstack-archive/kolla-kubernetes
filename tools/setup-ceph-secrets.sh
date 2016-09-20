#!/bin/bash -e
NAMESPACE=$(kolla-kubernetes resource-template create bootstrap ceph-bootstrap-initial-mon -o json | jq -r '.metadata.namespace')
pods=$(kubectl get pods --selector=job-name=ceph-bootstrap-initial-mon --namespace=$NAMESPACE --output=jsonpath={.items..metadata.name})
kubectl logs $pods --namespace=$NAMESPACE | grep FETCH_CEPH_KEYS | sed 's/^FETCH_CEPH_KEYS: //' > /tmp/$$
[ "x$(jq .failed /tmp/$$)" != "xfalse" ] && echo failed to read keys. && exit -1

for x in ceph.monmap ceph.client.radosgw.keyring ceph.client.mon.keyring ceph.client.admin.keyring; do
   sec=$(jq -r '."'$x'".content' /tmp/$$)
   name=$(echo $x | tr . -)
   (printf "\x1f\x8b\x08\x00\x00\x00\x00\x00" ; echo $sec | base64 -d ) | gzip -dc 2>/dev/null > /tmp/$$.1 || true
   kubectl create secret generic $name --from-file=data=/tmp/$$.1 --namespace=$NAMESPACE
done

rm -f /tmp/$$ /tmp/$$.1
