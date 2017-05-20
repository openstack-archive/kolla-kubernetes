#!/usr/bin/bash

#
# This script is a gift to sdake, so it can be used in ansible destroy workflow.
# It will check each node known to kubernetes cluster for any labels starting
# with 'kolla' and then remove it. 

kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}' \
 | awk '{print $1}' \
 | while read kube_host; do
   echo $kube_host
   labels=$(kubectl get nodes $kube_host -o jsonpath='{.metadata.labels}')
   for raw_label in $labels; do
     label=${raw_label%%:*}
     if [ -z "${label##kolla*}" ]; then
        kubectl label node $kube_host ${label%%:*}-
     fi
   done
done

exit 0
