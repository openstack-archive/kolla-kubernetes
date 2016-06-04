.. _mariadb-guide:

===========================
MariaDB in Kolla-Kubernetes
===========================

Overview
========

`MariaDB <https://mariadb.org/>`_ is the default persistant storage option for a Kolla-Kubernetes cluster.

Preparation and Deployment
==========================

MariaDB is self-sufficent, thus it's one of the first things you want to start while installing.

MariaDB must be boostrapped to set up the on-disk data structure before the process can start.  To bootstrap MariaDB::

    kolla-kubernetes bootstrap mariadb

To create the Replication Controller that will keep MariaDB running after boostrap has completed::

    kolla-kubernetes start mariadb

Verify Operation
================

TODO: Fill in more details

Debug an Instance
=================

MariaDB is configured to store it's database on the host at ``/var/lib/mysql``.  If there's contents from previous runs located there, the bootstrap will fail.

Until `patch 320744 <https://review.openstack.org/#/c/320744/>`_ is merged, you will need to build your own MariaDB container.