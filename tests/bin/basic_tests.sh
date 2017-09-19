#!/bin/bash -xe

function wait_for_vm {
    set +x
    count=0
    while true; do
        val=$(openstack server show $1 -f value -c OS-EXT-STS:vm_state)
        [ $val == "active" ] && break
        [ $val == "error" ] && openstack server show $1 && exit -1
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && exit -1
    done
    set -x
}

function wait_for_vm_ssh {
    set +ex
    count=0
    while true; do
        sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
            StrictHostKeyChecking=no cirros@$1 echo > /dev/null
        [ $? -eq 0 ] && break
        sleep 1;
        count=$((count+1))
        [ $count -gt 30 ] && echo failed to ssh. && exit -1
    done
    set -ex
}

function wait_for_http {
    set +ex
    count=0
    while true; do
        curl -Lsf "$1" > /dev/null
        [ $? -eq 0 ] && break
        sleep 1
        count=$((count+1))
        [ $count -gt 30 ] && echo Failed to contact "$1". && exit -1
    done
    set -ex
}

function scp_to_vm {
    sshpass -p 'cubswin:)' scp -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no "$2" cirros@$1:"$3"
}

function scp_from_vm {
    sshpass -p 'cubswin:)' scp -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no cirros@$1:"$2" "$3"
}

function ssh_to_vm {
    sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
        StrictHostKeyChecking=no cirros@$1 "$2"
}

function wait_for_cinder {
    set +ex
    count=0
    while true; do
        st=$(openstack volume show $1 -f value -c status)
        [ $st != "$2" ] && break
        sleep 1
        count=$((count+1))
        [ $count -gt 30 ] && echo Cinder volume failed. && exit -1
    done
    set -ex
}

HORIZON_URL=http://$(kubectl get svc horizon --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'):80/
wait_for_http $HORIZON_URL
curl -Lsf http://`kubectl get svc horizon --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`:80/ | grep 'OpenStack Dashboard'

# Test that endpoint list works correctly
timeout 120s openstack endpoint list

curl -o cirros.qcow2 \
    http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
echo testing cluster glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.clusterIP}'`:9292/
echo testing external glance-api
curl http://`kubectl get svc glance-api --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`:9292/
timeout 120s openstack image create --file cirros.qcow2 --disk-format qcow2 \
     --container-format bare 'CirrOS'

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

openstack security group list -f value -c ID | while read SG_ID; do
    neutron security-group-rule-create --protocol icmp \
        --direction ingress $SG_ID
    neutron security-group-rule-create --protocol tcp \
        --port-range-min 22 --port-range-max 22 \
        --direction ingress $SG_ID
done

openstack flavor create --public --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny || true

openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test
openstack server create --flavor=m1.tiny --image CirrOS \
     --nic net-id=admin test2

wait_for_vm test
wait_for_vm test2

openstack volume create --size 1 test

wait_for_cinder test creating

openstack server add volume test test
wait_for_cinder test available
wait_for_cinder test attaching

FIP=$(openstack floating ip create external -f value -c floating_ip_address)
FIP2=$(openstack floating ip create external -f value -c floating_ip_address)

openstack server add floating ip test $FIP
openstack server add floating ip test2 $FIP2

openstack server list

wait_for_vm_ssh $FIP

sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
    StrictHostKeyChecking=no cirros@$FIP curl 169.254.169.254

sshpass -p 'cubswin:)' ssh -o UserKnownHostsFile=/dev/null -o \
    StrictHostKeyChecking=no cirros@$FIP ping -W 20 -c 10 $FIP2

openstack volume show test -f value -c status
TESTSTR=$(uuidgen)
cat > /tmp/$$ <<EOF
#!/bin/sh -xe
mkdir /tmp/mnt
sudo /sbin/mkfs.vfat /dev/vdb
sudo mount /dev/vdb /tmp/mnt
sudo /bin/sh -c 'echo $TESTSTR > /tmp/mnt/test.txt'
sudo umount /tmp/mnt
EOF
chmod +x /tmp/$$

scp_to_vm $FIP /tmp/$$ /tmp/script
ssh_to_vm $FIP "/tmp/script"

openstack server remove volume test test
wait_for_cinder test in-use
wait_for_cinder test detaching
openstack server add volume test2 test
wait_for_cinder test available
wait_for_cinder test attaching
cat > /tmp/$$ <<EOF
#!/bin/sh -xe
mkdir /tmp/mnt
sudo mount /dev/vdb /tmp/mnt
sudo cat /tmp/mnt/test.txt
sudo cp /tmp/mnt/test.txt /tmp
sudo chown cirros /tmp/test.txt
EOF
chmod +x /tmp/$$
scp_to_vm $FIP2 /tmp/$$ /tmp/script
ssh_to_vm $FIP2 "/tmp/script"
scp_from_vm $FIP2 /tmp/test.txt /tmp/$$.2

diff -u <(echo $TESTSTR) /tmp/$$.2

sudo ip netns list > /tmp/$$
netnscount=$(wc -l /tmp/$$ | awk '{print $1}')
mntnetnscount=$(ls /run/netns/ | wc -l /tmp/$$ | awk '{print $1}')
[ $netnscount -ne 0 ]
[ $netnscount -eq $mntnetnscount ]
tf=/tmp/$$
echo -n > $tf
sudo docker ps -q | while read line; do
    sudo docker exec --user 0 $line /bin/sh -c 'ip netns list' >> $tf || true
done
cnetnscount=$(sort -u $tf | wc -l | awk '{print $1}')
[ $netnscount -eq $mntnetnscount ]

grep qrouter /tmp/$$
grep qdhcp /tmp/$$
