#!/bin/bash -e

KEYSTONE_EXTERNAL_IP=`kubectl get svc keystone-public --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`
KEYSTONE_ADMIN_PASSWD=`grep keystone_admin_password /etc/kolla/passwords.yml \
    | cut -d':' -f2 | sed -e 's/ //'`

cat > ~/keystonerc_admin <<EOF
unset OS_SERVICE_TOKEN
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASSWD
export OS_AUTH_URL=http://$KEYSTONE_EXTERNAL_IP:5000/v3
export PS1='[\u@\h \W(keystone_admin)]$ '
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne
EOF
