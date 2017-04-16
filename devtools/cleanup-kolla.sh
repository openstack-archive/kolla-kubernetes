helm delete mariadb --purge &
helm delete rabbitmq --purge &
helm delete memcached --purge &
helm delete keystone --purge &
helm delete glance --purge &
helm delete cinder-control --purge &
helm delete horizon --purge &
helm delete openvswitch --purge &
helm delete neutron --purge &
helm delete nova-control --purge &
helm delete nova-compute --purge &
sudo rm -rf /var/lib/kolla/volumes/*
