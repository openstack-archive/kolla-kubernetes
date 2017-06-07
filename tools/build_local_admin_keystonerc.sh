#!/bin/bash -e

# In some cases we need to use external keystone ip address. By default
# with no parameter passed, the script will behave as before.
# If 'ext' parameter passed, the script will use external keystone
# address.

if [ "x$1" == "xext" ]; then
KEYSTONE_CLUSTER_IP=`kubectl get svc keystone-public --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`
else
KEYSTONE_CLUSTER_IP=`kubectl get svc keystone-public --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`
fi

KEYSTONE_CLUSTER_PORT=`kubectl get svc keystone-public --namespace=kolla -o \
    jsonpath='{.spec.ports[0].port}'`
KEYSTONE_ADMIN_PASSWD=`grep keystone_admin_password /etc/kolla/passwords.yml \
    | cut -d':' -f2 | sed -e 's/ //'`

if [ -e /etc/kolla/certificates/haproxy-ca.crt ]; then
    CACERT="export OS_CACERT=/etc/kolla/certificates/haproxy-ca.crt"
else
    CACERT=""
fi

cat > ~/keystonerc_admin <<EOF
unset OS_SERVICE_TOKEN
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASSWD
export OS_AUTH_URL=http://$KEYSTONE_CLUSTER_IP:$KEYSTONE_CLUSTER_PORT/v3
export PS1='[\u@\h \W(keystone_admin)]$ '
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne
export OS_VOLUME_API_VERSION=2
$CACERT
EOF
