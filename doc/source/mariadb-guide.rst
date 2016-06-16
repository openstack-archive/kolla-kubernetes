.. _mariadb-guide:

===========================
MariaDB in Kolla-Kubernetes
===========================

Overview
========

`MariaDB <https://mariadb.org/>_ is the default persistant storage option for
`a Kolla-Kubernetes cluster.

Preparation and Deployment
==========================

MariaDB is self-sufficent, thus it's one of the first things you want to start
while installing.

MariaDB must be boostrapped to set up the on-disk data structure before the
process can start.  To bootstrap MariaDB::

    kolla-kubernetes bootstrap mariadb

To create the Replication Controller that will keep MariaDB running after
boostrap has completed::

    kolla-kubernetes run mariadb

Verify Operation
================

To find the database password::
    
    grep ^database_password /etc/kolla/passwords.yml

To find the IP address of the kubernetes service so you can test for
functionality on a machine inside of the Kubernetes cluster (e.g. running
Kube-proxy) but not running as a container::

    kubectl get svc mariadb

Once you know the IP address and password, you can check to see if a mysql
client running on a machine by appending the IP address to this command (e.g.
-h 192.0.2.0)::

    mysql -p -u root -h <ip_address>

Debug an Instance
=================

MariaDB is configured to store it's database on the host at
``/var/lib/mysql``.  If there's contents from previous runs located there, the
bootstrap will fail.
