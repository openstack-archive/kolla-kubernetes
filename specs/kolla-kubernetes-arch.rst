=============================
Kolla-kubernetes Architecture
=============================

OpenStack deployment requires multiple sequential steps to occur in workflow
like fashion. This puts the onus on Kubernetes to handle dependency management
and task ordering for each OpenStack service, which it currently doesn't. Using
the kolla-kubernetes fencing pod [1] as an example, the community will evaluate
adding an Operator(s) [2] as a means of handeling the deployment of OpenStack.

In addition, there will be an effort to use the Kubernetes native package
manager, the Helm project [3]. Kolla-kubernetes will evaluate using Helm charts
as a means for making each OpenStack service available in the native Kubernetes
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

The kolla-kubernetes community will write Operators in **Python** as part of the
1.0 release and revisit writing them in **Go** at a later date.

The kolla-kubernetes community will write Helm charts for each of the OpenStack
services.

Dependencies
------------

- Helm >= v2.0
- Kubernetes >= 1.4

Operators
=========

An Operator is defined as a container that executes code with the purpose of
managing the lifecycle of complex applications like OpenStack [4]. Here are
three potential models for OpenStack Operators in kolla-kubernetes:

Option 1:
There is a single OpenStack operator that handles the deployment of OpenStack.

Option 2a:
There are multiple Operators. One Operator per each **service** (nova, keystone,
neutron). There is a single OpenStack operator that orchestrates each
**service** Operator.

Option 2b:
There are multiple Operators. One Operator per each **micro service** (nova-api,
nova-conductor, nova-scheduler). There is a single OpenStack operator that
orchestrates each **micro service** Operator.

Code Outline
------------

The code for Operator(s) will exist in the kolla-kubernetes repo.

The Operator container(s) will be added as Kolla image(s). The Operator
container will include the Operator code and a script that will execute it.

Helm
====

Helm allows for kolla-kubernetes to be interwoven into the Kubernetes app
distribution system.  That way, an operator can search for and consume the
pieces of OpenStack as building blocks to assemble a real world deployment.
The user experiece is far greator using the Kubernetes native distribution
system.

Code Outline
------------

There will be a Helm chart for each OpenStack service.  The Helm charts will
premier in the kolla-kubernetes repo.  After reaching some stabilization, the
community can decide to publish the charts to the incubation directory in the
Kubernetes repo [5].

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
1. Write Operators required to run OpenStack
2. Write scripts that will execute the Operator
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
- [4] - https://github.com/coreos/etcd-operator/blob/master/doc/design/arch.png
- [5] - https://github.com/kubernetes/charts/tree/master/incubator
