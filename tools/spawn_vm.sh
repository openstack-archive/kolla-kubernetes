#!/bin/bash

set -x

kubectl get pods --namespace=kolla

curl -o cirros.qcow2 \
    http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img

echo Testing cluster glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`:9292/

echo Testing external glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`:9292/
timeout 120s openstack image create --file cirros.qcow2 --disk-format qcow2 \
     --container-format bare 'CirrOS'

echo Creating Networks...
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

echo Creating VMs...
openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test1
openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test2
