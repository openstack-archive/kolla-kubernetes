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

This is an advanced guide.  Before attempting to deploy on a
multi-node cluster, please follow the :doc:`quickstart` and ensure
that you have successfully deployed kolla-kubernetes on a single host
using the :doc:`kubernetes-all-in-one`.  This multi-node guide
requires quite a few system dependencies to be addressed by the
:doc:`quickstart`.

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


Pre-Requisites
==============

Follow the :doc:`quickstart`, configure your system, and do a
"Development Install" of kolla and kolla-kubernetes.  This is
absolutely required.


Configure Kolla
===============

For multi-node deployments, a docker registry is required since the
kubernetes nodes will not be able to find the kolla images that your
development machine has built.  Thus, we must configure kolla to name
the images correctly, so that we may easily push the images to the
right docker registry.

Add your docker registry settings in the kolla configuration file
```./etc/kolla/globals.yaml```.

::

  # Edit kolla config ./etc/kolla/globals.yml
  docker_registry: "<registry_url>"  # e.g. "gcr.io"
  docker_namespace: "<registry_namespace>  # e.g. "annular-reef-123"

Generate the kolla configurations, build the kolla images, and push
the kolla images to your docker registry.

::

  # Generate the kolla configurations
  pushd kolla
  sudo ./tools/generate_passwords.py  # (Optional: will overwrite)
  sudo ./tools/kolla-ansible genconfig
  popd


Build Kolla Images and Push to Docker Registry
==============================================

::

  # Set env variables to make subsequent commands cut-and-pasteable
  export DOCKER_REGISTRY="<registry_url>"
  export DOCKER_NAMESPACE="<registry_namespace>"
  export DOCKER_TAG="3.0.0"
  export KOLLA_CONTAINERS="mariadb memcached kolla-toolbox keystone horizon"

  # Build the kolla containers
  kolla-build $KOLLA_CONTAINERS --registry $DOCKER_REGISTRY --namespace $DOCKER_NAMESPACE

  # Authenticate with your docker registry
  #   This may not be necessary if you are using a cloud provider
  docker login

  # Push the newly-built kolla containers to your docker registry
  #   For GKE, change the command below to be "gcloud docker push"
  for i in $KOLLA_CONTAINERS; do
    docker push "$DOCKER_REGISTRY/$DOCKER_NAMESPACE/centos-binary-$i:$DOCKER_TAG"
  done


Configure Kolla-Kubernetes
==========================

Modify the kolla-kubernetes configuration file
```./etc/kolla-kubernetes/kolla-kubernetes.yml``` to set the number of
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
  storage_provider: "host"  # host, ceph, gce, aws
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
  kolla-kubernetes resource delete bootstrap mariadb  # workaround known issue #1
  kolla-kubernetes run mariadb
  kolla-kubernetes run memcached
  sleep 30  # wait for mariadb and memcached to start up
  kolla-kubernetes bootstrap keystone
  sleep 30  # wait for keystone to bootstrap in mariadb
  kolla-kubernetes run keystone
  sleep 30  # wait for keystone to start up
  kolla-kubernetes run horizon


Workflow Engine Create Resources
--------------------------------

A future Ansible Workflow Engine would individually call the discrete
bits of logic.

::

  kolla-kubernetes resource create disk mariadb
  kolla-kubernetes resource create pv mariadb
  kolla-kubernetes resource create pvc mariadb
  kolla-kubernetes resource create svc mariadb
  kolla-kubernetes resource create configmap mariadb
  kolla-kubernetes resource create bootstrap mariadb
  sleep 30  # wait for mariadb bootstrap to finish
  kolla-kubernetes resource delete bootstap mariadb  # workaround known issue #1
  kolla-kubernetes resource create pod mariadb
  kolla-kubernetes resource create svc memcached
  kolla-kubernetes resource create configmap memcached
  kolla-kubernetes resource create pod memcached
  kolla-kubernetes resource create svc keystone
  kolla-kubernetes resource create configmap keystone
  sleep 30  # wait for mariadb and memcached to start up
  kolla-kubernetes resource create bootstrap keystone
  sleep 30  # wait for keystone to bootstrap in mariadb
  kolla-kubernetes resource create pod keystone
  kolla-kubernetes resource create svc horizon
  kolla-kubernetes resource create configmap horizon
  sleep 30  # wait for keystone to start up
  kolla-kubernetes resource create pod horizon


Check Status of all Kolla-Kubernetes Resources
==============================================

Checking status is the same whether for operators or workflow engine.

::

  kolla-kubernetes resource status disk mariadb
  kolla-kubernetes resource status pv mariadb
  kolla-kubernetes resource status pvc mariadb
  kolla-kubernetes resource status svc mariadb
  kolla-kubernetes resource status configmap mariadb
  kolla-kubernetes resource status bootstrap mariadb
  kolla-kubernetes resource status pod mariadb
  kolla-kubernetes resource status svc memcached
  kolla-kubernetes resource status configmap memcached
  kolla-kubernetes resource status pod memcached
  kolla-kubernetes resource status svc keystone
  kolla-kubernetes resource status configmap keystone
  kolla-kubernetes resource status bootstrap keystone
  kolla-kubernetes resource status pod keystone
  kolla-kubernetes resource status svc horizon
  kolla-kubernetes resource status configmap horizon
  kolla-kubernetes resource status pod horizon


Delete all Kolla-Kubernetes Resources
=====================================

Deleting all resources is exactly executing the creation steps in
reverse.

Operator Delete Resources
-------------------------

::

  kolla-kubernetes kill horizon
  kolla-kubernetes kill keystone
  kolla-kubernetes kill memcached
  kolla-kubernetes kill mariadb
  kolla-kubernetes kill ceph


Workflow Engine Delete Resources
--------------------------------

::

  kolla-kubernetes resource delete pod horizon
  kolla-kubernetes resource delete configmap horizon
  kolla-kubernetes resource delete svc horizon
  kolla-kubernetes resource delete pod keystone
  kolla-kubernetes resource delete bootstrap keystone
  kolla-kubernetes resource delete configmap keystone
  kolla-kubernetes resource delete svc keystone
  kolla-kubernetes resource delete pod memcached
  kolla-kubernetes resource delete configmap memcached
  kolla-kubernetes resource delete svc memcached
  kolla-kubernetes resource delete pod mariadb
  kolla-kubernetes resource delete bootstrap mariadb
  kolla-kubernetes resource delete configmap mariadb
  kolla-kubernetes resource delete svc mariadb
  kolla-kubernetes resource delete pvc mariadb
  kolla-kubernetes resource delete pv mariadb
  kolla-kubernetes resource delete disk mariadb
