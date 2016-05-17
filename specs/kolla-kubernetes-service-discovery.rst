..
 This work is licensed under a Creative Commons Attribution 3.0 Unported
 License.

 http://creativecommons.org/licenses/by/3.0/legalcode

..

===========================
Kolla Kubernetes Service Discovery
===========================

https://blueprints.launchpad.net/kolla-kubernetes/+spec/kolla-kubernetes-service-discovery

Introduction
============

Kubernetes is highly dynamic and flexible environment in which location of
services could change as a result of multiple triggers. Discovering the
initial location of a service as well as post change location is essential
and required functionality for building flexible and elastic infrastructures
running on top of Kubernetes.

Problem description
===================

Kolla Kubernetes deploys OpenStack on top of Kubernetes cluster. In OpenStack
environment multiple services depend on other services,for example Keystone needs
Mariadb or Glance needs Keystone service.
In a conventional OpenStack environment the location of these services
are hardcoded in the service configuration files. In Kubernetes it is impossible
because the ip addresses of other services are not guaranteed to be known when
a service starts. Kolla Kubernetes needs to be able to discover and communicate
with these services dynamically.
Also for successful and efficient service discovery, the service naming
convention must be introduced and followed.

Use cases
---------
1. When Glance service (or any other OpenStack services) starts, it needs to
   learn the ip address of keystone container or any other dependent service.
2. To make Container Configuration process consistent, naming convention must
   be used.

Proposed change
===============

1.  Kolla-kubernetes is designed to by installed on Kubernetes cluster where
    dynamic dns add-in (skydns) is enabled.

2. Use service naming convention:

   service-name.default.svc.namespace

   Since most of services running on Kubernetes cluster do not have exposure to
   the outside infrastructure with the exception of keystone port 5000, horizon
   port 80, following simplified naming convention is proposed.

   For shared services, when one service is shared by many other services, use 
   default namespace:

   Kubernetes Namespace - openstack
   OpenStack service name - {service-name}

   For the case where high scale is required and one service will serve to only
   one another service, example mariadb serving only to keystone, then the
   namespace will be the name of consumer service.

   Kubernetes Namespace - {consumer service-name}
   OpenStack service name - {service-name}

   The resulting name for mariadb in shared service scenario will be:
   mariadb.openstack and in dedicated service scenarion: mariadb.keystone.

3. During the process of generating configuration files for services, use full
   dns names when referring toother services.

    Example is a resulting configuration to discover rabbitmq service.

    [oslo_messaging_rabbit]
    rabbit_hosts=rabbitmq:5672

Scope
-----

The scope of this BP is to make use of existing dynamic dns functionality in Kubernetes
and to introduce the service naming convention which should be followed while generating
service configuration files.

Security impact
---------------

None

Performance Impact
------------------

None

Alternatives
------------

Use Kubernetes environment variables, they provide similar functionality but with less
flexibility.

Implementation
==============

Assignee(s)
-----------

TODO

Milestones
----------

 TODO

Work Items
----------

1. Agree upon the proposed service naming convention.
2. Establish procedure of testing dynamic DNS functionality of the Kubernetes
   cluster.
3. Make sure Service/Container Configuration generation tools follows
   established naming convention.

Testing
=======
These features can easily be tested in any test bed.

Documentation Impact
====================
The documentation needs to be adjasted to reflect new features support.

References
==========
[1] http://kubernetes.io/docs/user-guide/services/#discovering-services

Issues
==========
1. With Docker version 1.11 and below, specifying custom dns server and host network
true when starting a docker container is impossible due to these options being
mutually exclusive. As a result until it is fixed in Docker version 1.12,
containers with HostNetwork: True cannot use dynamic DNS functionality.
