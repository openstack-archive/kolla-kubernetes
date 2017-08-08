#!/bin/bash -xe

PACKAGE_VERSION=0.7.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$6"
PIPELINE="$7"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
. "$DIR/setup_gate_common.sh"

# Installating required software packages
setup_packages $DISTRO $CONFIG

# Setting up iptables
setup_iptables

# Setting up an interface and a bridge
setup_bridge

# Setting up virt env, kolla-ansible and kolla-kubernetes
setup_kolla $BRANCH $CONFIG

tests/bin/setup_config_iscsi.sh "$2" "$4" "$BRANCH" "$TYPE"

tests/bin/setup_gate_loopback_lvm.sh

tools/setup_kubernetes.sh master

kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

tests/bin/setup_canal.sh

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true kolla_compute=true \
                         kolla_storage=true

tools/pull_containers.sh kube-system
tools/wait_for_pods.sh kube-system

tools/test_kube_dns.sh

# Setting up Helm
setup_helm_common

# Setting up namespace and secret
setup_namespace_secrets

# Setting up resolv.conf workaround
setup_resolv_conf_common

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume iscsid tgtd keepalived \
    placement-api placement-api-haproxy;

if [ "x$4" == "xironic" ]; then
kollakube res create configmap \
    ironic-api ironic-api-haproxy ironic-conductor ironic-conductor-tftp \
    ironic-dnsmasq ironic-inspector ironic-inspector-haproxy \
    ironic-inspector-tftp nova-compute-ironic;
fi

kollakube res create secret nova-libvirt

if [ "x$4" == "xhelm-compute-kit" ]; then
    tests/bin/deploy_compute_kit.sh "$4" "$2" "$BRANCH"
elif [ "x$4" == "xironic" ]; then
    tests/bin/iscsi_ironic_workflow.sh "$4" "$2" "$BRANCH"
elif [ "x$4" == "xhelm-operator" ]; then
    echo "Not yet implemented..." "$4" "$2" "$BRANCH"
else
    if [ "x$BRANCH" == "xt" ]; then
       tools/setup_registry.sh $DISTRO $TYPE $BRANCH
    fi
    tests/bin/iscsi_generic_workflow.sh "$4" "$2" "$BRANCH"
fi

. ~/keystonerc_admin

sudo pvs >> $WORKSPACE/logs/pvs.txt

sudo vgs >> $WORKSPACE/logs/vgs.txt

sudo lvs >> $WORKSPACE/logs/lvs.txt

cinder service-list >> $WORKSPACE/logs/cinder_service_list.txt

tests/bin/basic_tests.sh
tests/bin/horizon_test.sh
tests/bin/prometheus_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE


set +e
export LOGS_DIR=$WORKSPACE/logs/detail
echo "Capturing logs from environment."
mkdir -p ${LOGS_DIR}/k8s/etc
sudo cp -a /etc/kubernetes ${LOGS_DIR}/k8s/etc
sudo chmod 777 --recursive ${LOGS_DIR}/*

mkdir -p ${LOGS_DIR}/k8s
for OBJECT_TYPE in nodes \
                   namespace \
                   storageclass; do
  kubectl get ${OBJECT_TYPE} -o yaml > ${LOGS_DIR}/k8s/${OBJECT_TYPE}.yaml
done
kubectl describe nodes > ${LOGS_DIR}/k8s/nodes.txt

for NAMESPACE in $(kubectl get namespaces -o name | awk -F '/' '{ print $NF }') ; do
  for OBJECT_TYPE in svc \
                     pods \
                     jobs \
                     deployments \
                     daemonsets \
                     statefulsets \
                     configmaps \
                     secrets; do
    mkdir -p ${LOGS_DIR}/k8s/${NAMESPACE}/$OBJECT_TYPE
    kubectl get -n ${NAMESPACE} ${OBJECT_TYPE} -o yaml > \
      ${LOGS_DIR}/k8s/${NAMESPACE}/$OBJECT_TYPE/$OBJECT_NAME.yaml
  done
done

mkdir -p ${LOGS_DIR}/k8s/pods
kubectl get pods -a --all-namespaces -o json | jq -r \
  '.items[].metadata | .namespace + " " + .name' | while read line; do
  NAMESPACE=$(echo $line | awk '{print $1}')
  NAME=$(echo $line | awk '{print $2}')
  kubectl get --namespace $NAMESPACE pod $NAME -o json | jq -r \
    '.spec.containers[].name' | while read line; do
      CONTAINER=$(echo $line | awk '{print $1}')
      kubectl logs $NAME --namespace $NAMESPACE -c $CONTAINER > \
        ${LOGS_DIR}/k8s/pods/$NAMESPACE-$NAME-$CONTAINER.txt
  done
done

mkdir -p ${LOGS_DIR}/k8s/svc
kubectl get svc -o json --all-namespaces | jq -r \
  '.items[].metadata | .namespace + " " + .name' | while read line; do
  NAMESPACE=$(echo $line | awk '{print $1}')
  NAME=$(echo $line | awk '{print $2}')
  kubectl describe svc $NAME --namespace $NAMESPACE > \
    ${LOGS_DIR}/k8s/svc/$NAMESPACE-$NAME.txt
done

mkdir -p ${LOGS_DIR}/k8s/pvc
kubectl get pvc -o json --all-namespaces | jq -r \
  '.items[].metadata | .namespace + " " + .name' | while read line; do
  NAMESPACE=$(echo $line | awk '{print $1}')
  NAME=$(echo $line | awk '{print $2}')
  kubectl describe pvc $NAME --namespace $NAMESPACE > \
    ${LOGS_DIR}/k8s/pvc/$NAMESPACE-$NAME.txt
done

mkdir -p ${LOGS_DIR}/k8s/rbac
for OBJECT_TYPE in clusterroles \
                   roles \
                   clusterrolebindings \
                   rolebindings; do
  kubectl get ${OBJECT_TYPE} -o yaml > ${LOGS_DIR}/k8s/rbac/${OBJECT_TYPE}.yaml
done

mkdir -p ${LOGS_DIR}/k8s/descriptions
for NAMESPACE in $(kubectl get namespaces -o name | awk -F '/' '{ print $NF }') ; do
  for OBJECT in $(kubectl get all --show-all -n $NAMESPACE -o name) ; do
    OBJECT_TYPE=$(echo $OBJECT | awk -F '/' '{ print $1 }')
    OBJECT_NAME=$(echo $OBJECT | awk -F '/' '{ print $2 }')
    mkdir -p ${LOGS_DIR}/k8s/descriptions/${NAMESPACE}/${OBJECT_TYPE}
    kubectl describe -n $NAMESPACE $OBJECT > ${LOGS_DIR}/k8s/descriptions/${NAMESPACE}/$OBJECT_TYPE/$OBJECT_NAME.txt
  done
done

NODE_NAME=$(hostname)
mkdir -p ${LOGS_DIR}/nodes/${NODE_NAME}
echo "${NODE_NAME}" > ${LOGS_DIR}/nodes/master.txt
sudo docker logs kubelet 2> ${LOGS_DIR}/nodes/${NODE_NAME}/kubelet.txt
sudo docker logs kubeadm-aio 2>&1 > ${LOGS_DIR}/nodes/${NODE_NAME}/kubeadm-aio.txt
sudo docker images --digests --no-trunc --all > ${LOGS_DIR}/nodes/${NODE_NAME}/images.txt
sudo iptables-save > ${LOGS_DIR}/nodes/${NODE_NAME}/iptables.txt
sudo ip a > ${LOGS_DIR}/nodes/${NODE_NAME}/ip.txt
sudo route -n > ${LOGS_DIR}/nodes/${NODE_NAME}/routes.txt
sudo arp -a > ${LOGS_DIR}/nodes/${NODE_NAME}/arp.txt
cat /etc/resolv.conf > ${LOGS_DIR}/nodes/${NODE_NAME}/resolv.conf
sudo lshw > ${LOGS_DIR}/nodes/${NODE_NAME}/hardware.txt
if [ "x$INTEGRATION" == "xmulti" ]; then
  : ${SSH_PRIVATE_KEY:="/etc/nodepool/id_rsa"}
  : ${SUB_NODE_IPS:="$(cat /etc/nodepool/sub_nodes_private)"}
  for NODE_IP in $SUB_NODE_IPS ; do
    ssh-keyscan "${NODE_IP}" >> ~/.ssh/known_hosts
    NODE_NAME=$(ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} hostname)
    mkdir -p ${LOGS_DIR}/nodes/${NODE_NAME}
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo docker logs kubelet 2> ${LOGS_DIR}/nodes/${NODE_NAME}/kubelet.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo docker logs kubeadm-aio 2>&1 > ${LOGS_DIR}/nodes/${NODE_NAME}/kubeadm-aio.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo docker images --digests --no-trunc --all > ${LOGS_DIR}/nodes/${NODE_NAME}/images.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo iptables-save > ${LOGS_DIR}/nodes/${NODE_NAME}/iptables.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo ip a > ${LOGS_DIR}/nodes/${NODE_NAME}/ip.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo route -n > ${LOGS_DIR}/nodes/${NODE_NAME}/routes.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo arp -a > ${LOGS_DIR}/nodes/${NODE_NAME}/arp.txt
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} cat /etc/resolv.conf > ${LOGS_DIR}/nodes/${NODE_NAME}/resolv.conf
    ssh -i ${SSH_PRIVATE_KEY} $(whoami)@${NODE_IP} sudo lshw > ${LOGS_DIR}/nodes/${NODE_NAME}/hardware.txt
  done
fi

set -e

#
# Workflow specific tests
#
if [ "x$4" == "xironic" ]; then
   tests/bin/ironic_deploy_tests.sh "$4" "$2" "$BRANCH"
fi

exit 0
