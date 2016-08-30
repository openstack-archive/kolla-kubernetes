.. quickstart:

=================================
Kolla Kubernetes Quickstart Guide
=================================

Required services running
=========================

all-in-one
----------

=====================   ============
Component               Version
=====================   ============
Kubernetes              1.3
Docker                  1.10 or 1.12
=====================   ============

Generating Kubernetes Secrets
=============================

Secrets for each service must be generated before attempting to bootstrap
any services. The patch: https://review.openstack.org/#/c/354199/
provides a script which can be used to generate or to remove Secrets.

Before using this script, you MUST generate passwords by using
generate_passwords.py.

Script accepts 1 parameter: "create" or "delete".

::
    wget -O secret-generator.py goo.gl/QjpPlo
    secret-generator.py create

    # To delete Secrets for all services in passwords.yml run:
    secret-generator.py delete

Running Kolla-Kubernetes
========================

The following commands will allow you to bootstrap a running Horizon instance,
including all of its ordered dependencies.  Some kolla containers require
bootstrapping, while others do not.::

    kolla-kubernetes bootstrap mariadb
    kolla-kubernetes run mariadb
    kolla-kubernetes run memcached
    kolla-kubernetes bootstrap keystone
    kolla-kubernetes run keystone
    kolla-kubernetes run horizon

A similar pattern may be followed for Openstack services beyond horizon.
