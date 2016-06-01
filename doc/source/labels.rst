=================
Kubernetes Labels
=================

Service
-------

All resources associated with a service should be labeled with a key of ``service`` and a value with the service name

To query all pods with the mariadb service
::

    kubectl get po -l=service=mariadb

