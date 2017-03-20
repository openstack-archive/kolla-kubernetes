#!/bin/bash
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
systemctl start docker.service
systemctl start kubelet.service
