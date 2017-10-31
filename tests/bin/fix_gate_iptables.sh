#!/bin/bash -xe

#FIXME(kfox1111) just turn off iptables for now... It is getting in the way in zuulv3 and
#we dont have time to debug the exact changes to the infra. Reenable it properly in a
#follow on PS.
sudo iptables -F
exit

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
