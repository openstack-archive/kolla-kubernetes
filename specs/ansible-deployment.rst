====================================
Deploy kolla-kubernetes with Ansible
====================================

POC - Ansible support for Mariadb
https://review.openstack.org/#/c/334255/

Deploying and upgrading OpenStack is a workflow. Kubernetes is not a workflow
engine and it is not meant to act like one.  Kubernetes is good at managing
containers and Ansible is good at handing off an organized deployment to be
managed.  Instead of trying to make Kubernetes into something it isn't, the
work could be split by two tools that both specialize in their fields.

Problem description
===================

In order to do dependancy management in Kubernetes, it requires logic to be
added into containers, pods, and/or etcd, so that services will be cluster aware
during orchestration.  In doing so it requires the developers to account for all
scenarios and corner cases when architecting the containers.

Use Cases
=========

Ansible is capable of handling dependancy management and will be able to
orchestrate a cluster and hand it off to Kubernetes to be managed.

Ansible will be orchestrating the cluster by making CLI calls instead of using
a custom module.  The reason for this is to assist operators by providing an
interface to manage any day 1 or day 2 operations by hand.

Arguments
=========

Ansible is an additional tool to add to the project.  So there is an additional
dependancy here.
- Ansible wouldn't be adding any additional complexity. There would actually be
a net reduction in complexion because of the logic required to be built into
the containers in order to count for all use cases.

Kubernetes will not have complete control over the lifecycle of OpenStack.
Ansible will be handeling the bootstrapping, deployment, and the upgrade.
- Kubernetes upgrades at the moment only scale down a running container
and scale up the new one.  OpenStack upgrades are far more complex and require
a series of steps to be executes before a service can be successfully upgraded.
- Ansible can be removed when the community feels Kubernetes has reached a point
where the lifecycle can be fully managed by Kubernetes

< Add any pros/cons here so we can track any thoughts on the whether this is a
good choice or not >

Proposed change
===============

Use Ansible to orchestrate pods, service, configmaps, ect.

The CLI will be split out into sub commands that only manage/interact with a
single Kubernetes object. Ansible will plug into this interface and orchestrate
deployment through this provider.

Managed by the CLI:
  configmaps
  pods
  replication controllers
  deployments
  services
  < kubernetes_objects >
  querying Kubernetes objects
  rendering templates

Managed by Ansible:
  OpenStack deployment
  OpenStack upgrades
  < additional_workflows >

Dependencies
------------

- Ansible > 2.1

Security impact
---------------

The endpoint for the Kubernetes master can be assigned on startup.  The
community can recommend running anisble on the same host as the Kubernetes
master.  The Ansible Kubernetes module has an outline for SSL support [1], but
it's not fully implemented yet.

Performance Impact
------------------

Instead of relying on the CLI as a workflow, Ansible will provide the workflow
and make calls to the CLI.

Implementation
==============

Primary Assignee(s)
-----------
  Ryan Hallisey (rhallisey)
  Flavio Percoco (flaper87)

Other contributor(s):
  kolla-kubernetes team

Work Items
----------
1. Merge missing features into Kubernetes Ansible module [2]
2. Remodel the CLI into sub tasks to reflect the creation of each type of
   resource
3. Build an Ansible play for each service
4. Document how to deploy with Ansible
5. Document how an operator would use the CLI to run commands by hand
6. Add a dry run option so the operator can see exactly what is going to happen

<Please add new work items that are worth mentioning in the spec>

Documentation Impact
====================
This should simplify the docs.  Instead of a bunch of manually CLI steps things
will be driven by Ansible.  There will be addition docs for operators on how to
drive the deployment through the CLI.

References
==========

- [1] https://github.com/ansible/ansible-modules-extras/blob/devel/clustering/kubernetes.py#L211
- [2] https://github.com/ansible/ansible-modules-extras/pull/2466
