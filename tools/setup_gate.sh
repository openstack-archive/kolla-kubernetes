#!/bin/bash -xe
echo Setting up the gate...

yum install -y docker || apt-get install -y docker
systemctl start docker

docker ps -a

curl -Lo kubectl http://storage.googleapis.com/kubernetes-release/release/v1.4.0/bin/linux/amd64/kubectl
chmod +x kubectl

./kubectl get pods
