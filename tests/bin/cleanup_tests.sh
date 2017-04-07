#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

function delete_and_cleanup {

### Removing previous deployment
helm ls | grep $1 | awk {'print $1'} | xargs helm delete --purge
$DIR/tools/wait_for_pods_termination.sh kolla

### Cleaning service leftovers
helm install kolla/$1-cleanup --namespace=kolla --name $1-cleanup
$DIR/tools/wait_for_pods.sh kolla

### Checking for  leftovers
if [ $(openstack service list --column Name --format value | grep $1 | wc -l) -ne 0 ]; then
   exit -1
fi
if [ $(openstack user list --column Name --format value | grep $1 | wc -l) -ne 0 ]; then
   exit -1
fi
user='root'
password=$(python -c 'import yaml; print yaml.safe_load(open("/etc/kolla/passwords.yml"))["database_password"]')
if [ $(kubectl exec mariadb-0 -n kolla -- mysql --user=$user --password=$password -e 'show databases;' | grep $1 | wc -l) -ne 0 ]; then
   echo found:
   kubectl exec mariadb-0 -n kolla -- mysql --user=$user --password=$password -e 'show databases;' | grep $1
   exit -1
fi
}

for service in nova glance cinder neutron; do
    delete_and_cleanup $service
done

### All clean !!!
exit 0
