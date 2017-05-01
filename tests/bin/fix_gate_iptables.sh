#!/bin/bash -xe

l=$(sudo iptables -L INPUT --line-numbers | grep openstack-INPUT | \
    awk '{print $1}')
sudo iptables -D INPUT $l

#
# Temporary, just trying to understand why centos does not find this command
#
ls -al /usr/sbin/ip || true
find / -name ip | grep -v var

ip a | sed '/^[^1-9]/d;' | awk '{print $2}' | sed 's/://' | \
    grep -v '^lo$' | while read line; do
    sudo iptables -I INPUT 1 -i $line -j openstack-INPUT
done
