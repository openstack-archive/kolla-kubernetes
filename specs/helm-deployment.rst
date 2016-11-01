=================================
Deploy kolla-kubernetes with Helm
=================================

OpenStack requires dependency management between services in order to deploy
without issues.  The Helm project is the Kubernetes package manager which will
account for dependancy management.

Problem description
===================

In order to do dependancy management in Kubernetes, it requires logic to be
added into containers, pods, and/or etcd, so that services will be cluster aware
during orchestration.  In doing so it requires the developers to account for all
scenarios and corner cases when architecting the containers making it very
difficult to translate to real world operations.

Use Cases
=========

- Deployment
- Updates
- Upgrades
- Reconfigure

Proposed change
===============

Kolla-kubernetes will use the Helm project to handle service dependancies during
all lifecycle operations (deployment, updates, upgrades, reconfigure).

Helm may have some missing features to serve the complete lifecycle for
OpenStack.  The community will need to identify those gaps and fill them in the
Helm project.

Dependencies
------------

- Helm >= v2.0

Implementation
==============

Primary Assignee(s)
-----------
  Ryan Hallisey (rhallisey)

Other contributor(s):
  kolla-kubernetes core team

Work Items
----------
1. Write Helm charts for OpenStack services
2. Adjust the CLI to work with Helm
3. Identify any feature gaps in Helm

<Please add new work items that are worth mentioning in the spec>

Documentation Impact
====================

Docs will need to have a Helm setup guide [1].

References
==========

- [1] https://github.com/kubernetes/helm
