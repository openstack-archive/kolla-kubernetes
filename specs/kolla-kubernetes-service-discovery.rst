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
environment multiple services depends on other service, example keystone needs
mariadb or glance needs keystone service.
In conventional OpenStack environment usually the location of these services
are hardcoded in the service configuration files. In Kubernetes it is
impossible as the ip address is not known before POD with service gets
instantiated on one of Kubernetes workers node. Kolla Kubernetes needs to be
able to discover and communicate with these services dynamically.
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

1. Require dynamic DNS support on the cluster where Kolla Kubernetes installs
   OpenStack.

2. Use service naming convention:

   service-name.namespace
   
   Since most of services running on Kubernetes cluster do not have exposure to
   the outside infrastructure with the exception of keystone port 5000, horizon
   port 80, following simplified naming convention is proposed:

   Kubernetes Namespace - openstack
   container providing OpenStack service - {service-name}

   The resulting name for keystone container would be "keystone.openstack" and
   all references to keystone in other services configuration files should be
   by its full name.

3. During the process of generating configuration files for services, use full
   dns names when referring toother services.

    Example is a resulting configuration to discover rabbitmq service.

    [oslo_messaging_rabbit]
    rabbit_hosts=rabbitmg.openstack:5672

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

