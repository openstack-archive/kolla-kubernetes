#!/bin/bash -e
cat > /tmp/setup.$$ <<"EOF"
mkdir -p /data/kolla
df -h
dd if=/dev/zero of=/data/kolla/cinder-volumes.img bs=5M count=2048
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/cinder-volumes.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 100%
parted $LOOP set 1 lvm on
partprobe $LOOP
pvcreate $LOOP
vgcreate cinder-volumes $LOOP
pvs
vgs
echo "Finished prepping lvm storage..."
EOF
sudo bash /tmp/setup.$$
