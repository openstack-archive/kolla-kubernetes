.. user-values:

==================================
Kolla Kubernetes User Values Guide
==================================

Global helm values are aranged in a heirarchy to make it easy to set a value
and have it affect as many packages as need while still allowing you to
override specific packages values.

Root of the Tree
================

The root of the config tree is global.kolla. All global values show up under
that space.
::
global:
    kolla:

Kolla's globals
===============

There is an 'all' section that can affect all packages. This has the lowest
priority.
::
global:
    kolla:
        all:
            docker_registry: docker.io
            docker_namespace: kolla
            enable_kolla_logging: true


Simple Microservice Package heirarchy
=====================================

There are some packages that are very simple, such as mariadb, memcached,
rabbitmq, and horizon.

The all section:

Simple packages first look in the section named after their service name,
followed by the all section
::
global:
    kolla:
        mariadb:
            all:
                port: 42
 
This will set the tcp port used for mariadb-deployment and mariadb-svc both to
port 42. This allows you to easily set the value in one place.

Each individual package can override the specific values under their own kind
section:
::
global:
    kolla:
        mariadb:
            deployment:
                port: 43
            svc:
                port: 44

In addition to the service name section, for those packages that allow you to
launch more then one instance at a time by setting the element_name
(such as element_name=nova-mariadb), you can use that in additon to the service
name tree.
::
global:
    kolla:
        mariadb:
            all:
                enable_kolla_logging: true
        nova-mariadb:
            all:
                enable_kolla_logging: false
                port: 45

Element named sections take priority over service name sections.

2 Layer Microservice Package heirarchy
======================================

Most of the packages have a service name, service type, and service kind.
Glance is an exmaple of this. You have glance-api-deployment, glance-api-svc,
glance-registry-deployment and glance-registry-svc

For values that affect all of glance, the hearchy becomes:
::
global:
    kolla:
        glance:
            all:
                enable_kolla_logging: true

You can also affect all glance services with the same service type such as
glance-registry-deployment and glance-registry-svc:
::
global:
    kolla:
        glance:
            registry:
                all:
                    port: 1234

Or set values on a speciffic service kind only:
:: 
global:
    kolla:
        glance:
            registry:
                svc:
                    port: 1235

