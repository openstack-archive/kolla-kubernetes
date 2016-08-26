.. conventions:

============================
Kolla Kubernetes Conventions
============================

Redundant info
==============

Kubernetes or kolla-kubernetes resource names should not contain redundant information.

For example, instead of this:
tools/kolla_kubernetes.py resource-template create glance pod glance-api-pod

We should do this:
tools/kolla_kubernetes.py resource-template create glance pod api

Names are already unique to kubernetes object type and you must specify it. So, instead of this:
kubectl get pod glance-api-pod

We should do this:
kubectl get pod glance-api


Container Names
===============

Pods can contain multiple containers. To access them, you must specify the pod and the container. Names should be kept short for ease of use and to avoid redundant information. Also, in order to make it easy to switch from a command line to exec into one pod to another or get logs, we should standardize the primary container's name to always be 'main'.

Instead of calling pod glance-api's container glance-api, leading to this:
kubectl exec -it glance-api -c glance-api /bin/bash

We should do this:
kubectl exec -it glance-api -c main /bin/bash


Kubernetes/Kolla-kubernetes type consistency
============================================

The type in kolla-kubernetes cli's should match the type registered in kubernetes and it should be tagged appropriately on the file system.

So, the following should not create a deployment.
tools/kolla_kubernetes.py resource-template create glance pod api

If it needs to, it should be changed to:
tools/kolla_kubernetes.py resource-template create glance deployment api

The corresponding template should be named:
services/glance/api-deployment.yml.j2

OpenStack/Kolla-kubernetes type consistency
===========================================

To make it easy for an operator to switch between referencing things in kolla-kubernetes and in OpenStack, the OpenStack service name should be used in preference to some other name. Instead of this:
kubectl exec -it neutron-control ps ax
1 ?        Ss     1:06 /usr/bin/python2 /usr/bin/neutron-server

It should be:
kubectl exec -it neutron-server ps ax
1 ?        Ss     1:06 /usr/bin/python2 /usr/bin/neutron-server

