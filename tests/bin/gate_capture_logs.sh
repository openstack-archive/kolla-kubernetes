#!/bin/bash
set +xe
echo Capturing error logs.

exec 1<&-
exec 2<&-

exec 1<>$WORKSPACE/logs/gate_log_capture.txt
exec 2>&1

. ~/keystonerc_admin
mkdir -p $WORKSPACE/logs/pods
mkdir -p $WORKSPACE/logs/svc
mkdir -p $WORKSPACE/logs/ceph
mkdir -p $WORKSPACE/logs/openstack
sudo cp /var/log/messages $WORKSPACE/logs
sudo cp /var/log/syslog $WORKSPACE/logs
sudo cp -a /etc/kubernetes $WORKSPACE/logs
sudo chmod 777 --recursive $WORKSPACE/logs/*
kubectl get nodes -o yaml > $WORKSPACE/logs/nodes.yaml
kubectl get pods --all-namespaces -o yaml > $WORKSPACE/logs/pods.yaml
kubectl get jobs --all-namespaces -o yaml > $WORKSPACE/logs/jobs.yaml
kubectl get svc --all-namespaces -o yaml > $WORKSPACE/logs/svc.yaml
kubectl get deployments --all-namespaces -o yaml > \
    $WORKSPACE/logs/deployments.yaml
kubectl describe node $(hostname -s) > $WORKSPACE/logs/node.txt
kubectl get pods -a --all-namespaces -o yaml > $WORKSPACE/logs/pods.yaml
kubectl get configmaps -a --all-namespaces -o yaml > $WORKSPACE/logs/configmaps.yaml
sudo docker images > $WORKSPACE/logs/docker_images.txt
kubectl get pods -a --all-namespaces -o json | jq -r \
    '.items[].metadata | .namespace + " " + .name' | while read line; do
    NAMESPACE=$(echo $line | awk '{print $1}')
    NAME=$(echo $line | awk '{print $2}')
    echo $NAME | grep libvirt > /dev/null && \
    kubectl exec $NAME -c main --namespace $NAMESPACE \
        -- /bin/bash -c "virsh secret-list" > \
        $WORKSPACE/logs/virsh-secret-list.txt
    echo $NAME | grep libvirt > /dev/null && \
    kubectl exec $NAME -c main --namespace $NAMESPACE \
        -- /bin/bash -c "cat /var/log/libvirt/qemu/*" > \
        $WORKSPACE/logs/libvirt-vm-logs.txt
    kubectl exec $NAME -c main --namespace $NAMESPACE \
        -- /bin/bash -c "cat /var/log/kolla/*/*.log" > \
        $WORKSPACE/logs/openstack/$NAMESPACE-$NAME.txt
    kubectl describe pod $NAME --namespace $NAMESPACE > \
        $WORKSPACE/logs/pods/$NAMESPACE-$NAME.txt
    kubectl get pod $NAME --namespace $NAMESPACE -o json | jq -r \
        ".spec.containers[].name" | while read CON; do
        kubectl logs $NAME -c $CON --namespace $NAMESPACE > \
            $WORKSPACE/logs/pods/$NAMESPACE-$NAME-$CON.txt
    done
    kubectl get pod $NAME --namespace $NAMESPACE -o json | jq -r \
        '.metadata.annotations."pod.beta.kubernetes.io/init-containers"' \
        | grep -v '^null$' | jq -r '.[].name' | while read CON; do
        kubectl logs $NAME -c $CON --namespace $NAMESPACE > \
            $WORKSPACE/logs/pods/$NAMESPACE-$NAME-$CON.txt
    done
done
kubectl get svc -o json --all-namespaces | jq -r \
    '.items[].metadata | .namespace + " " + .name' | while read line; do
    NAMESPACE=$(echo $line | awk '{print $1}')
    NAME=$(echo $line | awk '{print $2}')
    kubectl describe svc $NAME --namespace $NAMESPACE > \
        $WORKSPACE/logs/svc/$NAMESPACE-$NAME.txt
done
sudo iptables-save > $WORKSPACE/logs/iptables.txt
sudo ip a > $WORKSPACE/logs/ip.txt
sudo route -n > $WORKSPACE/logs/routes.txt
cp /etc/kolla/passwords.yml $WORKSPACE/logs/
kubectl get pods -l system=openvswitch-vswitchd-network --namespace=kolla \
    | while read line; do
    kubectl logs $line --namespace=kolla -c initialize-ovs-vswitchd >> \
        $WORKSPACE/logs/ovs-init.txt
done
openstack catalog list > $WORKSPACE/logs/openstack-catalog.txt
str="timeout 6s ceph -s"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
sudo journalctl -u kubelet > $WORKSPACE/logs/kubelet.txt
str="timeout 6s ceph pg 1.1 query"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph/pg1.1.txt
str="timeout 6s ceph osd tree"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph/osdtree.txt
str="timeout 6s ceph health"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
str="cat /var/log/kolla/ceph/*.log"
kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph/osd.txt
str="timeout 6s ceph pg dump"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph/pgdump.txt
str="ceph osd crush tree"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph/crushtree.txt
df -h > $WORKSPACE/logs/df.txt
dmesg > $WORKSPACE/logs/dmesg
kubectl get secret ceph-client-nova-keyring --namespace=kolla -o yaml
kubectl get secret nova-libvirt-bin --namespace=kolla -o yaml
openstack volume list > $WORKSPACE/logs/volumes.txt
cp -a /etc/kolla $WORKSPACE/logs/
cp /usr/bin/rbd $WORKSPACE/logs/rbd.sh
[ -f /etc/nodepool/sub_nodes_private ] && cat /etc/nodepool/sub_nodes_private | while read line; do
    ssh -n $line sudo journalctl -u kubelet > $WORKSPACE/logs/kubelet-$line.txt
    ssh -n $line ps ax > $WORKSPACE/logs/ps-$line.txt
done
ovs-vsctl show > $WORKSPACE/logs/ovs.txt
arp -a > $WORKSPACE/logs/arp.txt
exit -1
