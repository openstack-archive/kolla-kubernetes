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
 * Service - A large piece of OpenStack functionality. Such as Nova or Neutron.
             It is often made up of multiple Elements launched from multiple
             Microservice Packages.
 * Microservice - a building block of a Service or multiple Services. One to
                  One relationship with a single instantiated Kubernetes Object
                  and provided by a single Microservice Package
 * Microservice Package - A small Package that contain only one Kubernetes
                          object description.
 * Orchestration - The logic/workflow of assembling basic things into a more
                   complex system.
 * Manual Orchestration - Orchestration done by a human being.
 * Automated Orchestration - Orchestration done by a piece of software.
 * Service Package - A single Package containing multiple embedded Microservice
                     Packages that use Helm to perform Automated Orchestration
                     to deploy a usable Service.

