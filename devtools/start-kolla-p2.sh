kubectl create namespace kolla
kubectl label node $(hostname) kolla_compute=true
kubectl label node $(hostname) kolla_controller=true
sudo kolla-ansible genconfig
kolla-kubernetes/tools/secret-generator.py create
kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume iscsid tgtd keepalived \
    placement-api placement-api-haproxy
kolla-kubernetes/tools/setup-resolv-conf.sh kolla
kolla-kubernetes/tools/helm_build_all.sh .



