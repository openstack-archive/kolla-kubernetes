.. _dns-guide:

============================
DNS in Kolla-Kubernetes
============================

Overview
========

`DNS`_ service provides the ability to dynamically discover services
in Kubernetes cluster.

Preparation and Deployment
==========================

DNS service requires two mandatory parameters configured in
etc/kolla-kubernetes/kolla-kubernetes.yml file.

dns_server_ip: "X.X.X.X"
dns_domain_name: "{domain_name}"

For dns_server_ip, the operator needs to choose an unused ip address
from the IP range allocated to Kubernetes service. This IP address
must be reachable from all PODs running on the kubernetes cluster.

Example: dns_server_ip: "10.57.0.2"

For dns_domain_name, the operator can specify any domain name which
are compliant with the existing DNS naming convention (RFC 1035).
This domain name will be automatically appended to all kubernetes
objects created for Kolla OpenStack.

Example: dns_domain_name: "openstack.local"

Kolla Kubernetes offers two ways to deploy DNS:

 - As a part of Ansible workflow of deploying Kolla Kubernetes.

 - Manual, by using kolla-kubernetes cli tool.

Manual deployment includes two steps:

 - Creation of DNS service using:

   kolla-kubernetes resource create svc skydns

 - Creation of DNS Replication Controller using:

   kolla-kubernetes resource create pod skydns

Kubernetes cluster modification
===============================
Kubernetes cluster must be made aware of the existence of DNS service. It
has done by adding two parameters to kubelet service startup command.

--cluster-dns="":    Same IP address for a cluster DNS server as in
                     kolla-kubernetes.yml
--cluster-domain="": Same Domain name as specified in kolla-kubernetes.yml

Verify Operation
================

In case of Ansible deployment of DNS, Ansible will be responsible to
verify the success of DNS deployment and report it to the operator.
Manual deployment can be verified by running:

 - kubectl get svc | grep dns
   dns service should be listed in the output

 - kubectl get pod | grep dns
   dns pod should be listed in the output and it should be in "Running" state.
