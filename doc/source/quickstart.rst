.. quickstart:

=================================
Kolla Kubernetes Quickstart Guide
=================================

Dependencies
============

=====================   ===========  ===========  =========================
Component               Min Version  Max Version  Comment
=====================   ===========  ===========  =========================
Ansible                 1.9.4        < 2.0.0      On deployment host
Docker                  1.10.0       < 1.11.0     On target nodes
Docker Python           1.6.0        none         On target nodes
Python Jinja2           2.8.0        none         On deployment host
Kubernetes              1.2.4        none         On all hosts
=====================   ===========  ===========  =========================


Since Docker is required to build images as well as be present on all deployed
targets, the kolla-kubernetes community recommends installing the official
Docker, Inc. packaged version of Docker for maximum stability and compatibility.

.. NOTE:: Docker 1.11.0 is not compatible with Kubernetes due to some issues in
Docker. The below command will install the latest docker and revert back to
1.10.3.

::

    curl -sSL https://get.docker.io | bash

    # CentOS
    sudo yum downgrade -y docker-engine-1.10.3-1.el7.centos

    # Ubuntu
    sudo apt-get remove docker-engine
    sudo apt-get install docker-engine=1.10.3-1

Docker needs to run with MountFlags=shared in order for Neutron to function
in 'thin' containers.  Change MountFlags from slave to shared and restart
Docker.

::
   # Edit /usr/lib/system/systemd/docker.service
   MountFlags=shared

   systemctl daemon-reload
   systemctl start docker

HyperCube
=========

HyperKube is series of containers that will run all the needed Kubernetes
services locally.

If you prefer to run Kubernetes in containers follow the :doc:`kubernetes-all
-in-one`.
