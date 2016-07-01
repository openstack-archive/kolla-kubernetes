=================
Kubernetes Labels
=================

Service
-------

All resources associated with a service should be labeled with a key of ``service`` and a value with the service name

To query all pods with the mariadb service
::

    kubectl get pods -l=service=mariadb

Type
----

Some OpenStack services (e.g. Keystone) have a single server process type.  Other services (e.g. Nova, Glance, Neutron, et al) have multiple categories of server processes within the same service.  For these cases, you should use a label of ``type`` and a value with the server process type's name.

To query all of the pods with the glance service of the API type
::

    kubectl get pods -l service=glance,type=api