..
 This work is licensed under a Creative Commons Attribution 3.0 Unported
 License.

 http://creativecommons.org/licenses/by/3.0/legalcode

..

==================================
Kolla Kubernetes Service Exposure
==================================

https://blueprints.launchpad.net/kolla-kubernetes/+spec/kolla-kubernetes-service-exposure

Introduction
============

The goal of Kolla Kubernetes cluster is to offer its clients/users the access to
OpenStack services running on a kubernetes cluster. Exposing OpenStack services
is one the most important part of this solution since if a user cannot access
these services, it makes Kolla-Kubernetes useless.

Problem description
===================

OpenStack services running on Kubernetes cluster use DNS names for flexibility.
These names as well as ip addresses associated with these services are internal
and external user has no means to discover and to access these name and ip
addresses directly. All externally accessible services must be exposed outside
of kubernetes cluster. In addition to exposing individual services, a user
also need a single reachable ip address to initiate a communication with
OpenStack's keystone running on Kolla Kubernetes cluster.


Use cases
---------
1. When an external user want to connect and start using OpenStack services, he
   or she needs to have reachable ip address.
2. In order to authenticate to Kolla-Kubernetes cluster a user must establish
   connection with Keystone Public end point.
3. In order to access any OpenStack services a user needs a reachable ip address
   and port.

Proposed change
===============

1. First use case can be resolved by a device or a software solution providing
   VIP functionality, the purpose of this reachable VIP is to serve as an entry
   point for outside users. All incoming requests for VIP and configured
   service ports, should be forwarded in round-robin fasion between "COMPUTE"
   nodes. It is not only allows accessing required service, but also offers
   loadbalancing and redundancy.
2. Second and third use case are addressed by exposing internal services
   using Kubernetes NodePort [0]. This feature will map a service port
   example 9191 to a predefined by kubernetes port (from the range
   Kubernetes allocates for NodePort). All compute nodes are notified and
   start listen on this NodePort.
   If compute node receives traffic destined to NodePort and the corresponding
   service POD is not running on this compute node, compute node will transfer
   packet to the compute hosting this pod.


Scope
-----

The scope of this BP is to ensure that OpenStack service are accessible to
outside users.

Security impact
---------------
Security impact
---------------

None

Performance Impact
------------------

None

Alternatives
------------

There are other kubernetes features which allow exposing services running on
a kubernetes cluster (loadbalancers, ingress) [1]

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

1. Agree upon the proposed service exposure technic.
2. Modify service definition templates to include type NodePort.
3. Modify services endpoint registration procedure for externally
   accessible services to use public VIP address instead of private
   dns names.


Testing
=======
This can be tested by introducing an haproxy with VIP configuration and ports
redirections to Kubernetes compute nodes.

Documentation Impact
====================
None

References
==========
[0] http://kubernetes.io/docs/user-guide/services/#type-nodeport
[1] http://kubernetes.io/docs/user-guide/ingress/

Issues
==========
None
