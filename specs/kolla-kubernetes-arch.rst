=============================
Kolla-kubernetes Architecture
=============================

OpenStack deployment requires multiple sequential steps to occur in workflow
like fashion. This puts the onus on Kubernetes to handle dependency management
and task ordering for each OpenStack service, which it currently doesn't. The
community will evaluate the existing kolla-kubernetes fencing pod [1] in
context of adding an Operator [2] as a means of handeling the deployment of
OpenStack.

In addition, there will be an effort to use the Kubernetes native package
manager, the Helm project [3]. Kolla-kubernetes will evaluate using Helm charts
as a means for making the application available in the native Kubernetes
ecosystem and increase consumability of Kolla containers in real world
deployments and across communities.

Problem description
===================

In order to execute the OpenStack deployment workflow, the community needs a way
to handle dependancy management. Dependancy management requires logic to be
added into containers so that services will be cluster aware during
orchestration.

The kolla-kubernetes community will evaluate using Operators [1][2] to fill the
gap of dependancy management.

Proposed change
===============

The kolla-kubernetes community will write Operators in *Python* as part of the
1.0 release and revisit writing them in *Go* at a later date.

The kolla-kubernetes community will write Helm charts for each of the OpenStack
services.

Dependencies
------------

- Helm >= v2.0
- Kubernetes >= 1.4

Operators
=========

An Operator is defined as code that will exist in each container to allow for
orchestration of complex applications like OpenStack.

Code Outline
------------

The code for Operators will exist in the kolla-kubernetes repo and there will be
one Operator per service.

The Operator code will be templated into the Kolla images with a flag for
kolla-kubernetes builds.  The kolla-kubernetes build will include the Operator
and a script that will execute it.

   {% if project_build == 'kolla-kubernetes' %}

Helm
====

Helm allows for kolla-kubernetes to be interwoven into the Kubernetes app
distribution system.  That way, an operator can use the pieces of OpenStack
as building blocks to assemble a real world deployment.

Code Outline
------------

There will be a Helm chart for each OpenStack service.  The Helm charts will
premier in the kolla-kubernetes repo.  After reaching some stabilization, the
community can decide to publish the charts to the incubation directory in the
Kubernetes repo [4].

Implementation
==============

Primary Assignee(s)
-------------------
  Ryan Hallisey (rhallisey)
  Steven Dake (sdake - Delta-Alpha-Kilo-Echo)
  kolla-kubernetes team

Other contributor(s):

Work Items
----------
1. Write Operators for each OpenStack service
2. Write script(s) that will execute the Operator
3. Write Helm charts for OpenStack services
4. Adjust the CLI to work with Operators and Helm

<Please add new work items that are worth mentioning in the spec>

Documentation Impact
====================

< more docs >

References
==========

- [1] - https://review.openstack.org/#/c/383922/
- [2] - https://coreos.com/blog/introducing-operators.html
- [3] - https://github.com/kubernetes/helm
- [4] - https://github.com/kubernetes/charts/tree/master/incubator
