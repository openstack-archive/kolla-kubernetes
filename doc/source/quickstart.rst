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
  1.10.3.  For different Debian or Ubuntu distributions, you may need to use 
  ``apt-cache madison docker-engine`` to get the correct version.

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

For Ubuntu 12.04/14.04 and other distributions that use upstart instead of
systemd, run the following:

::

    mount --make-shared /

Kubernetes Setup with HyperKube
===============================

HyperKube is series of containers that will run all the needed Kubernetes
services locally.  Follow the :doc:`kubernetes-all-in-one` documentation.

`The Kubernetes documentation explains setting up a larger cluster
<http://kubernetes.io/docs/getting-started-guides/>`_.

Installing Kolla
================

::

    git clone https://git.openstack.org/openstack/kolla
    sudo pip install kolla/
    cd kolla
    sudo cp -r etc/kolla /etc/

Generating Configuration Files
==============================

Kolla can be used to generate config files.  The config files will be populated based on what's in globals.yml and passwords.yml then placed in ``/etc/kolla``.  From inside the kolla directory use the following command.

::

    ./tools/kolla-genpwd
    ./tools/kolla-ansible genconfig

``kolla-genpwd`` will generate passwords and encryption keys and populate the passwords.yml file.  ``kolla-ansible genconfig`` will generate the config files.

Installing Kolla-Kubernetes
===========================

::

    pip install kolla-kubernetes

The extra configuration files that Kolla-kubernetes requires aren't where
the kolla-kubernetes CLI expects them to be located, therefore we need to
use an environment variable, ``K8S_SERVICE_DIR``.

To install any service supported by Kolla-Kubernetes, say mariadb:

::

    export K8S_SERVICE_DIR=/usr/local/share/kolla-kubernetes/services/
    kolla-kubernetes run mariadb
