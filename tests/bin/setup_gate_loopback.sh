#!/bin/bash -e
cat > /tmp/setup.$$ <<"EOF"
mkdir -p /data/kolla
df -h
dd if=/dev/zero of=/data/kolla/ceph-osd0.img bs=5M count=1024
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/ceph-osd0.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 512m
parted $LOOP mkpart 2 513m 100%
partprobe $LOOP
dd if=/dev/zero of=/data/kolla/ceph-osd1.img bs=5M count=1024
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/ceph-osd1.img
parted $LOOP mklabel gpt
parted $LOOP mkpart 1 0% 512m
parted $LOOP mkpart 2 513m 100%
partprobe $LOOP
EOF
sudo bash /tmp/setup.$$
