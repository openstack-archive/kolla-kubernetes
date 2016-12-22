#!/bin/bash -e
cat > /tmp/setup.$$ <<"EOF"
mkdir -p /data/kolla
df -h
dd if=/dev/zero of=/data/kolla/cinder-volumes.img bs=5M count=2048
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/cinder-volumes.img
parted -s $LOOP mklabel gpt
parted -s $LOOP mkpart 1 0% 100%
parted -s $LOOP set 1 lvm on
partprobe $LOOP
pvcreate -y $LOOP
vgcreate -y cinder-volumes $LOOP
echo "Finished prepping lvm storage on $LOOP"
EOF
sudo bash /tmp/setup.$$
