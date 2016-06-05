=====
Usage
=====

Bootstrapping
=============

OpenStack services need to be bootstrapped before they can run. This is handled
by a Kubernetes Job. In order to run the Kubernetes Job, use the ``bootstrap``
flag.

::

   kolla-kubernetes bootstrap <service>

Running an OpenStack service
============================

Running a service involves starting pod(s), service(s), and creating
configmap(s). Use the ``run`` flag to create and run these objects.

::

   kolla-kubernetes run <service>

Removing OpenStack services
===========================

A service will have pod(s), service(s), configmap(s), and job(s) associated with
it. Use the ``kill`` command to remove all of these objects.

::

   kolla-kubernetes kill <service>

Debugging
=========

Use the ``-d`` flag to run in debug mode.

::

   kolla-kubernetes -d run <service>

Using the All flag
==================

In order run a task for all services, use the ``all`` flag instead of naming a
service.

::

   kolla-kubernetes bootstrap all
   kolla-kubernetes run all
