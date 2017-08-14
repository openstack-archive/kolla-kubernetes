#!/bin/bash -xe

PACKAGE_VERSION=0.7.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$6"
PIPELINE="$x7"
IP=172.18.0.1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
. "$DIR/setup_gate_common.sh"

# Installating required software packages
setup_packages $DISTRO $CONFIG

# Setting up iptables
setup_iptables

# Setting up an interface and a bridge
setup_bridge

# Setting up virt env, kolla-ansible and kolla-kubernetes
setup_kolla

if [ "x$CONFIG" == "xexternal-ovs" ]; then
    sudo rpm -Uvh https://repos.fedorapeople.org/openstack/openstack-newton/rdo-release-newton-4.noarch.rpm || true
    sudo yum install -y openvswitch
    sudo systemctl start openvswitch
    sudo ovs-vsctl add-br br-ex
fi

tests/bin/setup_config.sh "$2" "$4" "$BRANCH"

tests/bin/setup_gate_loopback.sh

tools/setup_kubernetes.sh master

kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

#
# Setting up networking on master, before slave nodes in multinode
# scenario will attempt to join the cluster
tests/bin/setup_canal.sh

# Turn up kube-proxy logging enable only for debug 
# kubectl -n kube-system get ds -l 'component=kube-proxy-amd64' -o json \
#   | sed 's/--v=4/--v=9/' \
#   | kubectl apply -f - && kubectl -n kube-system delete pods -l 'component=kube-proxy-amd64'

if [ "x$CONFIG" == "xceph-multi" ]; then
    NODES=1
    cat /etc/nodepool/sub_nodes_private | while read line; do
        NODES=$((NODES+1))
        echo $line
        ssh-keyscan $line >> ~/.ssh/known_hosts
        scp tools/setup_kubernetes.sh $line:
        scp tests/bin/fix_gate_iptables.sh $line:
        scp /usr/bin/kubectl $line:kubectl
        NODENAME=$(ssh -n $line hostname)
        ssh -n $line bash fix_gate_iptables.sh
        ssh -n $line sudo iptables-save > $WORKSPACE/logs/iptables-$line.txt
        ssh -n $line sudo setenforce 0
        if [ "x$2" == "xubuntu" ]; then
           ssh -n $line sudo apt-get -y remove open-iscsi
        else
           ssh -n $line sudo yum remove -y iscsi-initiator-utils
        fi
        ssh -n $line sudo mv kubectl /usr/bin/
        ssh -n $line bash setup_kubernetes.sh slave "$(cat /etc/kubernetes/token.txt)" "$(cat /etc/kubernetes/ip.txt)"
        set +xe
        count=0
        while true; do
          c=$(kubectl get nodes --no-headers=true | wc -l)
          [ $c -ge $NODES ] && break
          count=$((count+1))
          [ $count -gt 30 ] && break
          sleep 1
        done
        [ $count -gt 30 ] && echo Node failed to join. && exit -1
        set -xe
        kubectl get nodes
        kubectl label node $NODENAME kolla_compute=true
    done
fi

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true

if [ "x$CONFIG" != "xceph-multi" ]; then
    kubectl label node $NODE kolla_compute=true
fi

tools/pull_containers.sh kube-system
tools/wait_for_pods.sh kube-system

tools/test_kube_dns.sh

# Setting up Helm
setup_helm_common

tools/build_example_yaml.py

# Setting up namespace and secret
setup_namespace_secrets

# Setting up resolv.conf workaround
setup_resolv_conf_common

tunnel_interface=docker0
if [ "x$CONFIG" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    tunnel_interface=$interface
fi

tests/bin/build_test_ceph.sh $CONFIG $DISTRO $IP $tunnel_interface $BRANCH

helm install kolla/ceph-admin-pod --version $PACKAGE_VERSION \
    --namespace kolla --name ceph-admin-pod --set kube_logger=false

helm install kolla/ceph-rbd-daemonset --version $PACKAGE_VERSION \
    --namespace kolla --name ceph-rbd-daemonset --set kube_logger=false

tools/wait_for_pods.sh kolla

str="ceph -w"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph.log &

for x in kollavolumes images volumes vms; do
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool create $x 64; ceph osd pool set $x size 1; ceph osd pool set $x min_size 1"
done
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool delete rbd rbd --yes-i-really-really-mean-it"

tools/setup_simple_ceph_users.sh

tools/setup_rbd_volumes.sh --yes-i-really-really-mean-it "$BRANCH"

str="grep 'key =' /etc/ceph/ceph.client.admin.keyring | awk '{print "'$3'"}'"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c \
    "$str" > /tmp/$$
cat /tmp/$$
key=$(cat /tmp/$$)

git clone https://github.com/kfox1111/charts/
cd charts
git checkout -b ceph-provisioner origin/ceph-provisioner
cd stable/ceph-provisioner
helm dep up
cd ../..
helm install stable/ceph-provisioner --name ceph-provisioner \
  --namespace kolla-system \
  --set adminSecret.key=$key,userSecret.name=admin,adminSecret.key=$key,monitors[0]=$(hostname -s)
cd ..

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume keepalived nova-compute-ironic\
    ironic-api ironic-api-haproxy ironic-conductor ironic-dnsmasq \
    ironic-inspector ironic-inspector-haproxy ironic-inspector-tftp \
    ironic-conductor-tftp placement-api placement-api-haproxy;

kollakube res create secret nova-libvirt

if [ "x$CONFIG" == "xhelm-entrypoint" ]; then
   tests/bin/ceph_workflow_service.sh "$4" "$2" "$6"
else
   tests/bin/ceph_workflow.sh "$4" "$2" "$6"
fi

. ~/keystonerc_admin
kubectl get pods --namespace=kolla
kubectl get svc --namespace=kolla
tests/bin/basic_tests.sh
tests/bin/horizon_test.sh
tests/bin/prometheus_tests.sh
tests/bin/cleanup_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE
