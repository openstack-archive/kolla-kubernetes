#!/bin/bash -xe

l=$(sudo iptables -L INPUT --line-numbers | grep openstack-INPUT | \
    awk '{print $1}')
sudo iptables -D INPUT $l

if [ -f /usr/sbin/ip ]; then
   ip_command="/usr/sbin/ip a"
else
   ip_command="ip a"
fi
$ip_command | sed '/^[^1-9]/d;' | awk '{print $2}' | sed 's/://' | \
    grep -v '^lo$' | while read line; do
    sudo iptables -I INPUT 1 -i $line -j openstack-INPUT
done
