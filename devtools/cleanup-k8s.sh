#!/bin/bash
# Note: This script wipes out the kubernetes environment completely.
# Note: this script may have to be run twice with a reboot inbetween.

kubeadm reset
systemctl stop kubelet.service
docker ps -a --format '{{.ID}}' | xargs docker stop
docker ps -a --format '{{.ID}}' | xargs docker rm -f
systemctl stop docker.service
systemctl stop kubelet.service
rm -rf /etc/kubernetes
rm -rf ~/.helm/
rm -rf ~/.kube/
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /var/run/calico/
rm -rf /var/etcd/
rm -rf /etc/cni/
rm -rf /run/kubernetes
rm -rf /var/lib/kubelet
rm -rf /opt/cni
rm -rf /var/lib/kolla/volumes/mariadb/*
rm -rf /var/lib/kolla/volumes/rabbitmq/*
rm -rf /var/lib/kolla/volumes/glance/*
systemctl start docker.service
systemctl start kubelet.service
