#!/bin/bash -xe

### Removing previous glance deployment
helm ls | grep glance | awk {'print $1'} | xargs helm delete --purge 

helm ls 

### Cleaning up glance leftovers
helm install --debug kolla/glance-cleanup --namespace=kolla --name glance-cleanup

openstack service list
if [ $(openstack service list --column Name --format value | grep glance | wc -l) -ne 0 ]; then
   exit 1
fi
openstack user list
if [ $(openstack user list --column Name --format value | grep glance | wc -l) -ne 0 ]; then
   exit 1
fi
exit 0
