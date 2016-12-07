.. _terms:

=========================
Terms in Kolla-Kubernetes
=========================

Overview
========

It is difficult to understand a system and discuss it without using a common
set of terminology. This document will try and lay out some common terminology.

Terms
=====

 * Container - A Docker Container provided by the Kolla-Kubernetes project
 * Package - A Kubernetes Helm package provided by the Kolla-Kubernetes project
 * Chart - The source code to a Package
 * Microservice - A Small Package that contain only one Kubernetes object
                  description. The building blocks of larger things.
 * Release - A single instance of a Package on the running system.
 * Element - One or more Releases on the system can form a larger usable
             building block. For example, a rabbit server and a rabbit service
             are two separate Packages but are instantiated together to form an
             Element. Multiple Elements using the same Packages can be
             co'exist on the same system. For example, a rabbit Element for
             Nova, and a different rabbit Element for Neutron.
 * Template - Source code that, when processed by Helm along with Values
              passed during instantiaton, creates the final Kubernetes object.
              It is provided as part of a Chart and compiled into a Package.
