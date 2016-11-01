=============================
Kolla-kubernetes Architecture
=============================

OpenStack deployment requires multiple sequential steps to occur in workflow
like fashion. This puts the onus on Kubernetes to handle dependency management
and task ordering for each OpenStack service, which it currently doesn't. Using
the kolla-kubernetes fencing pod [1] as an example, the community will evaluate
adding Kubernetes Operators [2] as a means of handling the deployment of
OpenStack.

In addition, there will be an effort to use the Kubernetes native package
manager, the Helm project [3]. Kolla-kubernetes will evaluate using Helm charts
as a means for making each OpenStack service available in the native Kubernetes
ecosystem and increase consumability of Kolla containers in real world
deployments and across communities.

Problem description
===================

In order to execute the OpenStack deployment workflow, the community needs a way
to handle dependency management. Dependency management requires logic to be
added into containers so that services will be cluster aware during
orchestration.

The kolla-kubernetes community will evaluate using Kubernetes Operators [1][2]
to fill the gap of dependency management.

Proposed change
===============

The kolla-kubernetes community will write Kubernetes Operators in **Python** as
part of the 1.0 release and revisit writing them in **Go** at a later date. The
reason for this is because Go lacks the ecosystem required by the TC in order to
allow for it to be used as part of OpenStack. Specifically, it has to do with
tools and code distribution.

The kolla-kubernetes community will write Helm charts for each of the OpenStack
services.

Dependencies
------------

- Helm >= v2.0
- Kubernetes >= 1.4

Kubernetes Operator
===================

*Kubernetes Controller* - A Kubernetes Controller is a piece of code that
manages the lifecycle of a complex application [4].
*Kubernetes Operator* - A Kubernetes Operator is defined as a containerized
Kubernetes Controller [5].

The Kubernetes Operator for deploying Keystone will perform the following tasks:
  1. Check Mariadb exists
  2. Create the Keystone database
  3. Create users
  4. Execute any additional startup tasks to bring the service to a ready state
  5. Starts the Keystone service

User perspective of a Kubernetes Operator
------------------------------------------

OpenStack lifecycle management is a workflow and Kubernetes Operators are the
implementation of it. However, using a kubernetes Operator needs to be optional
because a user may want to handle all the necessary lifecycle steps by hand.
Therefore, the Kubernetes Operator needs to be detached from the services
themselves so that it can be flexible.

OpenStack as a whole is highly customizable and flexible.  For a lifecycle tool
to be successful, the tool needs to match OpenStack's customizability and
flexibility traits in order to achieve maximum operability.

Layering
--------

As an example, a user needs the ability to choose the layer that best fits their
needs. That could be dropping all upper layers to be more manual, but more
flexible or vice versa.
  1. OpenStack service
  2. Kubernetes service pod
  3. Helm package
  4. Micro service Kubernetes Operator
  5. Service Kubernetes Operator
  6. OpenStack Kubernetes Operator

Kubernetes Operator Design
--------------------------

The goal of this section is to provide the proper Kubernetes Operator design
so that OpenStack lifecycle management will abide by the follow principles:

  - Granular
  - Consumable
  - Flexible
  - Customizable
  - Debuggable

Here are four potential models for how the community will use Kubernetes
Operators to deploy OpenStack in kolla-kubernetes:

Option 1:
There is a single OpenStack kubernetes operator that handles the deployment of
OpenStack.

  - Though the simplicity is appealing here, this option is concerning because
    it does not reflect the complexity, consumability, or granularity OpenStack
    lifecycle management requires.

Option 2:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**service** (nova, keystone, neutron). There is a single OpenStack kubernetes
operator that orchestrates each **service** Kubernetes Operator.

  - This option provides a good amount of granularity in that there is a clear
    separation between the different layers of abstraction.  This could have
    more layers or it might be the right amount of abstraction a user is looking
    for.

Option 3:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**micro service** (nova-api, nova-conductor, nova-scheduler). Above that,
there is a Kubernetes Operator per **service** that controls the micro
service Kubernetes Operator. At the top level, there is a single OpenStack
Kubernetes Operator that orchestrates each **service** Kubernetes
Operator.

  - This option provides a high amount of granularity with every service being
    thinned out to the microservice level. This option will be the most costly
    in terms of code written since every service will have multiple Kubernetes
    Operators. Also, there needs to be an account of the additional layering
    being more granular.  Will more layers be better for user at the cost of
    complexity?

Option 4:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**role** (compute, controller, networking, monitoring). There is a single
OpenStack Kubernetes Operator that orchestrates each **role** Kubernetes
Operator.

  - This option provides an average amount of granularity.  The roles would
    have to be completely customizable and exposed to the kubernetes operator.
    There isn't a defined layering to handle an individual lifecycle task for a
    specific service of a role in this model.

Code Outline
------------

The Controller code will live in the kolla-kubernetes repo. The Kubernetes
Operator container(s) will be added as kolla image(s) and exist in the
kolla-kubernetes repo.

Helm
====

Helm allows for kolla-kubernetes to be interwoven into the Kubernetes app
distribution system.  That way, a Kubernetes Operator can search for and consume
the pieces of OpenStack as building blocks to assemble a real world deployment.
The user experiece is far greator using the Kubernetes native distribution
system.

Code Outline
------------

There will be a Helm chart for each OpenStack service [6].  The Helm charts will
premier in the kolla-kubernetes repo.  After reaching some stabilization, the
community can decide to publish the charts to the incubation directory in the
Kubernetes repo [7].

Implementation
==============

Primary Assignee(s)
-------------------
  Ryan Hallisey (rhallisey)
  Steven Dake (sdake)
  Kevin Fox (kfox1111)
  Pete Birley (portdirect)
  Michal Jastrzebski (inc0)
  Mark Giles (mgiles)
  Takashi Sogabe (sogabe)
  kolla-kubernetes team

< add your name here >

Work Items
----------
1. Write Kubernetes Operators required to run OpenStack
2. Write scripts that will execute the Kubernetes Operator
3. Write Helm charts for OpenStack services
4. Adjust the CLI to work with Kubernetes Operators and Helm

<Please add new work items that are worth mentioning in the spec>

Documentation Impact
====================

< more docs >

References
==========

- [1] - https://review.openstack.org/#/c/383922/
- [2] - https://coreos.com/blog/introducing-operators.html
- [3] - https://github.com/kubernetes/helm
- [4] - https://coreos.com/blog/introducing-the-etcd-operator.html
- [5] - https://github.com/coreos/etcd-operator/blob/master/doc/design/arch.png
- [6] - https://github.com/sapcc/openstack-helm
- [7] - https://github.com/kubernetes/charts/tree/master/incubator
