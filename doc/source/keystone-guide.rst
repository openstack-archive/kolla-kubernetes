.. _keystone-guide:

============================
Keystone in Kolla-Kubernetes
============================

Overview
========

`Keystone <http://docs.openstack.org/developer/keystone/>`_ provides Identity,
Token, Catalog and Policy services for a Kolla-Kubernetes cluster.

Preparation and Deployment
==========================

Keystone requires a running instance of MariaDB to bootstrap and will attempt
to use Memcached as a cache.  However, the bootstrap process should repeatedly
attempt, with backoff, to bootstrap until both of the dependent services are
up.

Keystone must be boostrapped to set up the database before the process can
start.  To bootstrap Keystone::

    kolla-kubernetes bootstrap keystone

To create the Replication Controller that will keep MariaDB running after
boostrap has completed::

    kolla-kubernetes start keystone

Verify Operation
================

While debugging install issues, you might start to wonder if Keystone
is operating properly.  On a machine running inside of the Kubernetes
cluster (e.g. running kube-proxy) with the kolla passwords at
``/etc/kolla/passwords.yml`` you can run::

    export KEYSTONE_CLUSTER_IP=`kubectl get svc keystone-public -o jsonpath='{.spec.clusterIP}'`
    export KEYSTONE_ADMIN_PASSWD=`grep keystone_admin_password /etc/kolla/passwords.yml | cut -d':' -f2 | sed -e 's/ //'`
    curl -i   -H "Content-Type: application/json"   -d '
    { "auth": {
        "identity": {
          "methods": ["password"],
          "password": {
            "user": {
              "name": "admin",
              "domain": { "id": "default" },
              "password": "'"$KEYSTONE_ADMIN_PASSWD"'"
            }
          }
        }
      }
    }'   http://$KEYSTONE_CLUSTER_IP:5000/v3/auth/tokens ; echo


The response should look something like thos::

  HTTP/1.1 201 Created
  Date: Thu, 16 Jun 2016 21:01:11 GMT
  Server: Apache/2.4.6 (CentOS) mod_wsgi/3.4 Python/2.7.5
  X-Subject-Token: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Vary: X-Auth-Token
  x-openstack-request-id: req-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXX
  Content-Length: 283
  Content-Type: application/json

  {"token": {"issued_at": "2016-06-16T21:01:12.718951Z", "audit_ids": ["V-XXXXXXXXXXXXXXXXXXXX"], "methods": ["password"], "expires_at": "2016-06-16T22:01:12.718347Z", "user": {"domain": {"id": "default", "name": "Default"}, "id": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", "name": "admin"}}}

Debugging Bootstrap
===================

To check the status of the bootstrap job, look for the pod labeled keystone-bootstrap::

    kubectl get pod

And look for a pod starting with the name ``keystone-bootstrap``.  An example
output while the jobs are failing looks like this (don't be confused by the
``completed`` status -- that means the job completed but not necessarily
successfully)::

    NAME                       READY     STATUS      RESTARTS   AGE
    keystone-bootstrap-t2mmb   0/4       Completed   4          36s

You can look at which jobs are failing by looking at the name of the job (in
this example ``keystone-bootstrap-t2mmb`` and typing::

    kubectl describe pod keystone-bootstrap-t2mmb

The bootstrap involves starting containers running a series of bootstrap jobs;
when all of the bootstraps have completed, there should be no pods starting with
the name ``keystone-bootstrap``.

Debugging An Instance
=====================

To enter a pod to debug::

    export KEYSTONE_POD_NAME=`kubectl get pod -l service=keystone -o jsonpath='{.items[*].metadata.name}'`
    kubectl exec -it $KEYSTONE_POD_NAME /bin/bash

Logs are usually under /var/log/kolla/

TODO: Fill in more details