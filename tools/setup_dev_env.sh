#!/bin/bash -xe
DEV_BASE=${DEV_BASE:-/opt}
KOLLA_K8S=${DEV_BASE}/kolla-kubernetes

pushd ${DEV_BASE}
# create build environment and run
ceph_setup () {
    ssh vagrant@kube2 'bash -s' < kolla-kubernetes/tests/bin/setup_gate_loopback.sh

    echo "kolla_base_distro: centos" >> kolla-ansible/etc/kolla/globals.yml
    cat kolla-kubernetes/tests/conf/ceph-all-in-one/kolla_config \
        >> kolla-ansible/etc/kolla/globals.yml
    cat kolla-kubernetes/tests/conf/ceph-all-in-one/kolla_kubernetes_config \
        >> kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml

    sed -i "s/initial_mon:.*/initial_mon: kube2/" \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml
    interface="eth1"
    echo "tunnel_interface: $interface" >> kolla-ansible/etc/kolla/globals.yml
    echo "storage_interface: $interface" >> \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s/172.17.0.1/$(cat /etc/nodepool/primary_node_private)/" \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml
}

config_setup () {
    kolla-kubernetes/tools/secret-generator.py
    kolla-ansible/tools/kolla-ansible genconfig

    crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
    crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_user nova
    UUID=$(awk '{if($1 == "rbd_secret_uuid:"){print $2}}' /etc/kolla/passwords.yml)
    crudini --set /etc/kolla/nova-compute/nova.conf libvirt rbd_secret_uuid $UUID

    # Keystone does not seem to invalidate its cache on entry point addition.
    crudini --set /etc/kolla/keystone/keystone.conf cache enabled False

    sed -i 's/log_outputs = "3:/log_outputs = "1:/' /etc/kolla/nova-libvirt/libvirtd.conf
    sed -i 's/log_level = 3/log_level = 1/' /etc/kolla/nova-libvirt/libvirtd.conf

    sed -i \
        '/\[global\]/a osd pool default size = 1\nosd pool default min size = 1\nosd crush chooseleaf type = 0\ndebug default = 5\n'\
        /etc/kolla/ceph*/ceph.conf

    kolla-kubernetes/tools/fix-mitaka-config.py
}

k8s_setup () {
    kubectl get nodes -L kubeadm.alpha.kubernetes.io/role --no-headers | awk '$NF ~ /^<none>/ { print $1}' | while read NODE ; do
            kubectl label node $NODE --overwrite kolla_compute=true
        done
    kubectl label node 172.16.35.12 --overwrite kolla_controller=true
    kubectl create namespace kolla
    kolla-kubernetes/tools/secret-generator.py create
    kolla-kubernetes/tools/setup-resolv-conf.sh kolla
}

ceph_startup () {
    kollakube template configmap ceph-mon ceph-osd > /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml

    kollakube template bootstrap ceph-bootstrap-initial-mon > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-bootstrap-initial-mon succeeded

    kolla-kubernetes/tools/setup-ceph-secrets.sh

    # ceph mon-bootstrap
    kollakube res delete bootstrap ceph-bootstrap-initial-mon
    kollakube template pod ceph-mon > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-mon running

    # ceph-osd0 / osd1 bootstrap
    kollakube template pod ceph-bootstrap-osd0 > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    sed -i "s|loop0|loop2|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-bootstrap-osd0 succeeded

    kollakube template pod ceph-bootstrap-osd1 > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    sed -i "s|loop1|loop3|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-bootstrap-osd1 succeeded

    # cleanup ceph bootstrap
    kollakube res delete pod ceph-bootstrap-osd0
    kollakube res delete pod ceph-bootstrap-osd1

    # ceph osd0 / osd1 startup
    sed -i "s|^ceph_osd_data_kube2:|ceph_osd_data_dev:|g"  \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s|^ceph_osd_journal_kube2:|ceph_osd_journal_dev:|g"  \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml
    sed -i "s|/kube2/loop|/dev/loop|g" \
        kolla-kubernetes/etc/kolla-kubernetes/kolla-kubernetes.yml

    kollakube template pod ceph-osd0 > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    sed -i "s|loop0|loop2|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-osd0 running

    kollakube template pod ceph-osd1 > /tmp/kube.yaml
    sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
    sed -i "s|loop1|loop3|g"  /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-osd1 running

    kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
        "cat /etc/ceph/ceph.conf" > /tmp/ceph.conf
    kubectl create configmap ceph-conf --namespace=kolla \
        --from-file=ceph.conf=/tmp/ceph.conf

    # ceph admin startup
    kollakube template pod ceph-admin ceph-rbd > /tmp/kube.yaml
    kubectl create -f /tmp/kube.yaml
    kolla-kubernetes/tools/wait_for_pods.py kolla ceph-admin,ceph-rbd running

    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "ceph -s"

    for x in kollavolumes images volumes vms; do
        kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
            -c "ceph osd pool create $x 64; ceph osd pool set $x size 1; ceph osd pool set $x min_size 1"
    done
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
        -c "ceph osd pool delete rbd rbd --yes-i-really-really-mean-it"

    kolla-kubernetes/tools/setup_simple_ceph_users.sh
    kolla-kubernetes/tools/setup_rbd_volumes.sh --yes-i-really-really-mean-it 2
}

helm_setup () {
    rm -rf ~/.helm
    helm init

    kubectl delete deployment tiller-deploy --namespace=kube-system; helm init
    # wait for tiller service to be up / available
    while true; do
        echo 'Waiting for tiller to become available.'
        helm version | grep Server > /dev/null && \
            RUNNING=True || RUNNING=False
        [ $RUNNING == "True" ] && \
            break || true
        sleep 5
    done

    kolla-kubernetes/tools/helm_build_all.sh ~/.helm/repository/kolla
    helm repo remove kollabuild
    kolla-kubernetes/tools/helm_buildrepo.sh ~/.helm/repository/kolla 10192 kolla &
    helm repo update

    kollakube res create configmap \
        mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
        nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
        glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
        neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
        openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
        nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
        nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
        cinder-scheduler cinder-volume keepalived;
    kollakube res create secret nova-libvirt
}

ceph_setup
config_setup
k8s_setup
ceph_startup
helm_setup
kolla-kubernetes/tests/bin/ceph_workflow_service.sh devenv centos 2 172.16.35.11 eth1
