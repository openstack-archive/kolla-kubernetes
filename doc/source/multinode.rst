.. multi-node:

=================================
Kolla Kubernetes Multi-Node Guide
=================================

This guide documents how to deploy kolla-kubernetes within a
multi-node Kubernetes cluster.  It will guide you through all of the
dependencies required to deploy Horizon, the Openstack Admin Web
Interface.  It works for kubernetes clusters supporting various
storage providers including GCE compute disks, AWS EBS, Ceph RBD, and
even local host mounts if you are developing multi-node on an
all-in-one system.

Following this guide will result in a minimal kolla-kubernetes
multi-node deployment consisting of:

- 1 mariadb instance
- 1 memcached instance
- 3 keystone instances
- 3 horizon instances

The end result will be a working Horizon admin interface and its
dependencies deployed with all of the self-healing and auto-wiring
benefits that a kubernetes cluster has to offer.  You should be able
to destroy kubernetes nodes at will, and the system should self-heal
and maintain state as pods migrate from destroyed nodes to new nodes.
You may also destroy *all* kubernetes nodes, then bring some back, and
the system should again self-heal.  Because we are using network
volumes, mariadb state is maintained since its network volume will
follow the pod as it is rescheduled from one node to the next.

Required services running
=========================

multinode
---------

=====================   ===========
Component               Min Version
=====================   ===========
Kubernetes              1.3
Docker                  1.10 or 1.12
Ceph (or any shared     Infernalis
storage)
=====================   ============

Config
======

For multi-node deployments, a docker registry is required since the
kubernetes nodes will not be able to find the kolla images that your
development machine has built.  Thus, we must configure kolla to name
the images correctly, so that we may easily push the images to the
right docker registry.

Add your docker registry settings in the kolla configuration file
``/etc/kolla/globals.yaml``.

::

  docker_registry: "<host_ip_address>:4000"

Build Kolla Images and Push to Docker Registry
==============================================

::

  export DOCKER_REGISTRY="<host_ip_address>:4000"

  # Build the kolla containers
  kolla-build mariadb memcached kolla-toolbox keystone horizon --registry $DOCKER_REGISTRY --push

Configure Kolla-Kubernetes
==========================

Modify the kolla-kubernetes configuration file
``/etc/kolla-kubernetes/kolla-kubernetes.yml`` to set the number of
instance replicas.  In addition, set the storage_provider settings to
match your environment.

::

  # Edit kolla-kubernetes config ./etc/kolla-kubernetes/kolla-kubernetes.yml

  ########################
  # Kubernetes Cluster
  ########################
  keystone_replicas: "3"
  horizon_replicas: "3"

  ########################
  # Persistent Storage
  ########################
  storage_provider: "ceph"  # host, ceph, gce, aws
  storage_ceph:
    keyring: /etc/ceph/ceph.client.admin.keyring
    monitors:
    - x.x.x.x
    - y.y.y.y
    pool: rbd
    secretName: pkt-ceph-secret
    ssh_user: root
    user: admin


Known Issues
============

#1. On GCE, the mariadb pod is unable to mount the network drive that
was prior mounted by the mariadb-bootstrap job, until the
mariadb-bootstrap job is deleted.  The same should also occur for AWS
and Ceph.

#2. When running Kubernetes, Ceph RBD volumes will not auto-unlock
when Kubernetes nodes disappear, causing problems when a pod migrates
to a new node and cannot mount the required volume.  This was supposed
to have been fixed in Kubernetes 1.3, but we have been unable to
verify it working.  Details are found in the in this `kubernetes pull
request <https://github.com/kubernetes/kubernetes/pull/26351>`_.


Create all Kolla-Kubernetes Resources
=====================================

Execute the following commands to create the kolla-kubernetes
multi-node cluster.  There are two unique perspectives, that of an
operator and that of a workflow engine.  The workflow engine drives
the same CLI subcommands that are accessible to operators.

However, since the workflow engine does not yet exist, the shortcut
workflow commands as defined in the quickstart are still supported.

All of the commands below are cut and pasteable.

Operator Create Resources
-------------------------

::

  kolla-kubernetes bootstrap ceph  # adds ceph secret, no-op for storage_provider!=ceph
  kolla-kubernetes bootstrap mariadb
  sleep 30  # wait for mariadb bootstrap to finish
  kolla-kubernetes resource delete mariadb bootstrap  # workaround known issue #1

  kolla-kubernetes run mariadb
  kolla-kubernetes run memcached
  kolla-kubernetes bootstrap keystone
  kolla-kubernetes run keystone
  kolla-kubernetes run horizon

Check Status of any Kubernetes Resource
=======================================

Checking status of a Kubernetes resource either from querying Kubernetes or the
CLI::

  kolla-kubernetes resource status mariadb disk
  kolla-kubernetes resource status mariadb pv
  kolla-kubernetes resource status mariadb pvc
  kolla-kubernetes resource status mariadb svc
  kolla-kubernetes resource status mariadb configmap
  kolla-kubernetes resource status mariadb bootstrap
  kolla-kubernetes resource status mariadb pod

Deleting Kolla-Kubernetes Resources
=====================================

Using the command line to delete resources will delete the pod, service,
configmap, and job associated with the service.

::

  kolla-kubernetes kill keystone
