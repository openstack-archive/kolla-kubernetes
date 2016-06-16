.. _mariadb-guide:

============================
Keystone in Kolla-Kubernetes
============================

Overview
========

`Keystone <http://docs.openstack.org/developer/keystone/>_ provides Identity,
`Token, Catalog and Policy services for a Kolla-Kubernetes cluster.

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

    kolla-kubernetes start mariadb

Verify Operation
================

To find the IP address of the kubernetes services so you can test for
functionality on a machine inside of the Kubernetes cluster (e.g. running
Kube-proxy) but not running as a container::

    kubectl get svc keystone-admin keystone-public

To find the Keystone admin password::

    grep keystone_admin_password /etc/kolla/passwords.yml

With the Keystone IP address and the admin password, replace <ADMINPW> with
the admin password and <SERVICE_IP> with the service IP for the keystone-
public service::

    curl -i   -H "Content-Type: application/json"   -d '
    { "auth": {
        "identity": {
          "methods": ["password"],
          "password": {
            "user": {
              "name": "admin",
              "domain": { "id": "default" },
              "password": "<ADMINPW>"
            }
          }
        }
      }
    }'   http://<SERVICE_IP>:5000/v3/auth/tokens ; echo

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

To check the status of the bootstrap job, type::

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

Once the bootstrap has completed, there should be no pods starting with the
name ``keystone-bootstrap``.

Debugging An Instance
=====================

TODO: Fill in more details
