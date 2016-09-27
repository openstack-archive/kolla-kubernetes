#!/bin/bash -xe
echo Setting up the gate...

sudo yum install -y docker || sudo apt-get install -y docker
sudo systemctl start docker

docker ps -a

curl -Lo kubectl http://storage.googleapis.com/kubernetes-release/release/v1.4.0/bin/linux/amd64/kubectl
chmod +x kubectl

./kubectl get pods
