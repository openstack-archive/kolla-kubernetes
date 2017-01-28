#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

### Removing previous glance deployment
helm ls | grep glance | awk {'print $1'} | xargs helm delete --purge
$DIR/tools/wait_for_pods_termination.sh kolla

### Cleaning up glance leftovers
helm install kolla/glance-cleanup --namespace=kolla --name glance-cleanup
$DIR/tools/wait_for_pods.sh kolla

### Checking for glance leftovers
if [ $(openstack service list --column Name --format value | grep glance | wc -l) -ne 0 ]; then
   exit 1
fi
if [ $(openstack user list --column Name --format value | grep glance | wc -l) -ne 0 ]; then
   exit 1
fi
user='root'
password=$(python -c 'import yaml; print yaml.load(open("/etc/kolla/passwords.yml"))["database_password"]')
if [ $(kubectl exec mariadb-0 -n kolla -- mysql --user=$user --password=$password -e 'show databases;' | grep glance | wc -l) -ne 0 ]; then
   exit 1
fi

### All clean!!!
exit 0
