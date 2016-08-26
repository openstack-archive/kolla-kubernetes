.. conventions:

============================
Kolla Kubernetes Conventions
============================

Why
===

It can be difficult for operators to learn and operate OpenStack as it has
so many parts. It is even more difficult when multiple projects use terms
inconsistently:
 * OpenStack
 * Kubernetes
 * Kolla-Kubernetes

We need follow some conventions to minimize operator difficulty in this
area.

OpenStack is generally hard to debug as it has so many moving parts.
If the kolla-kubernetes system itself or the links between kolla-kubernetes,
kubernetes, and OpenStack are not smooth, it adds to the debugging pain.

Any additional pain added by the deployment tools cause operators to look
to other deployment tools to lessen the pain. In order to keep operators
using kolla-kubernetes we need to minimize the amount of unnecessary extra
work the deployment tool requires of them. Something that, to a developer may
seem to be a small amount of effort, can turn out to add up to noticeable
amounts of additional time spent over years of usage in operations.

The conventions here are also intended to make it easier for new developers
to scan through the code base and find what they are looking for.

Redundant info
==============

Kubernetes or kolla-kubernetes resource names should not contain redundant
information.

For example, instead of this:
tools/kolla_kubernetes.py resource-template create foo pod foo-api-pod

We should do this:
tools/kolla_kubernetes.py resource-template create foo pod api

Names are already unique to kubernetes object type and you must specify it. So,
instead of this:
kubectl get pod foo-api-pod

We should do this:
kubectl get pod foo-api


Type appending
==============
There are some cases where the type needs to be added back in for clarity in
the name of something. This most often happens with volumes, as you may have a
foo secret and a foo configmap for the foo deployment.

The type should always be added back with a '-' at the end of the
very end of the name.

Example with volume names:
volumes:
- name: foo-secret
  secret:
    name: foo
- name: foo-configmap
  configMap:
    name: foo


Container Names
===============

Pods can contain multiple containers. To access them, you must specify the pod
and the container. Names should be kept short for ease of use and to avoid
redundant information. Also, in order to make it easy to switch from a command
line to exec into one pod to another or get logs, we should standardize the
primary container's name to always be 'main'.

Instead of calling pod foo-api's container foo-api, leading to this:
kubectl exec -it foo-api -c foo-api /bin/bash
kubectl exec -it foo-registry -c foo-registry /bin/bash

We should do this:
kubectl exec -it foo-api -c main /bin/bash
kubectl exec -it foo-registry -c main /bin/bash


Kubernetes/Kolla-kubernetes type consistency
============================================

The type in kolla-kubernetes cli's should match the type registered in
kubernetes and it should be tagged appropriately on the file system.

So, the following should not create a deployment.
tools/kolla_kubernetes.py resource-template create foo pod api

If it needs to, it should be changed to:
tools/kolla_kubernetes.py resource-template create foo deployment api

The corresponding template should be named:
services/foo/api-deployment.yml.j2

OpenStack/Kolla-kubernetes type consistency
===========================================

To make it easy for an operator to switch between referencing things in
kolla-kubernetes and in OpenStack, the OpenStack service name should be
used in preference to some other name. Instead of this:
kubectl exec -it neutron-control ps ax
1 ?        Ss     1:06 /usr/bin/python2 /usr/bin/neutron-server

It should be:
kubectl exec -it neutron-server ps ax
1 ?        Ss     1:06 /usr/bin/python2 /usr/bin/neutron-server
