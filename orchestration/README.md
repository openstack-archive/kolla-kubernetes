# Kolla-Kubernetes Quickstart

Temporary instructions for installing Kolla-Kubernetes with Ansible from Docker image.

## Edit vars

Configure the installation.

```bash
git clone http://github.com/openstack/kolla-kubernetes
cd kolla-kubernetes
vi ansible/group_vars/all.yml
```

## Create orchestration image

Build and push orchestration images.
Note: Requires image registry 

```bash
sudo docker build . --tag="localhost:30400/kolla-kubernetes-orchestration:latest"
sudo docker push localhost:30400/kolla-kubernetes-orchestration
```

## Create namespace and context

Create kolla namespace and context and use kolla context.

```bash
kubectl create ns kolla
kubectl config set-context kolla --cluster=kubernetes --user=kubernetes-admin --namespace=kolla
kubectl config use-context kolla
```
## Create orchestration manifest

```yaml
# kolla.yml

apiVersion: v1
kind: Pod
metadata:
  name: kolla
spec:
  containers:
    - name: kolla-controller
      image: localhost:30400/kolla-kubernetes-orchestration
      command:
        - sleep
        - infinity
```

## Deploy

Start orchestration pod, exec into container and run ansible-playbook.
Note: You will need to wait for pod to be available before exec'ing into it.

```bash
kubectl create -f kolla.yml -n kolla
kubectl exec -ti kolla /bin/bash -n kolla
cd /kolla-kubernetes/orchestration
ansible-playbook deploy.yml --extra-vars "@/kolla-kubernetes/ansible/group_vars/all.yml"  --extra-vars "kolla_internal_address=<IP address>"
```