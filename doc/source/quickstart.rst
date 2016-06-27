.. quickstart:

=================================
Kolla Kubernetes Quickstart Guide
=================================

Dependencies
============

=====================   ===========  ===========  =========================
Component               Min Version  Max Version  Comment
=====================   ===========  ===========  =========================
Ansible                 2.00         none         On deployment host
Docker                  1.10.0       < 1.11.0     On target nodes
Docker Python           1.6.0        none         On target nodes
Python Jinja2           2.8.0        none         On deployment host
Kubernetes              1.2.4        none         On all hosts
=====================   ===========  ===========  =========================

.. NOTE:: Kolla (which provides the templating) is sensitive about the
  Ansible version.  Mainline currently requires 2.0.x or above.

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

    # Ubuntu (Assuming "Trusty Tahr" 14.04 LTS)
    sudo apt-get remove docker-engine
    sudo apt-get install docker-engine=1.10.3-0~trusty

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

Installing Kolla and Kolla-Kubernetes
=====================================

Follow the instructions for a **full install** if you are not a developer.
Choose a **development install** if you will frequently pull or contribute
patches.  A development install allows you to ```git pull``` within the
repository in order to use the latest code without having to re-install.  It
also removes the need to copy files to system directories such as /etc/kolla,
and allows you to use ```git diff``` to see all code or resource file changes
that you or the system has made.

Kolla-kubernetes depends on configuration files (and images) that are generated
from kolla.  When fully installed, kolla default configuration files
(globals.yml) are expected in ``/etc/kolla`` (globals.yml).  Newly generated
configuration files are placed in the same directory.  Kolla's
``generate_passwords.py`` creates a passwords.yml file which contains passwords
and encryption keys.  Kolla's ``kolla-ansible genconfig`` will generate the
config files for each kolla service container based on the contents of
globals.yml and passwords.yml


Full Install
------------

::

    # Clone Kolla
    git clone https://git.openstack.org/openstack/kolla

    # Install Kolla
    pushd kolla
    sudo pip install .
    sudo cp -r ./etc/kolla /etc
    popd

    # Generate Kolla Configuration Files
    pushd kolla
    sudo ./tools/generate_passwords.py
    sudo ./tools/kolla-ansible genconfig
    popd

    # Clone Kolla-Kubernetes
    git clone https://git.openstack.org/openstack/kolla-kubernetes

    # Install Kolla-Kubernetes
    pushd kolla-kubernetes
    sudo pip install .
    sudo cp -r ./etc/kolla-kubernetes /etc
    popd


Development Install
-------------------

::

    # Clone Kolla
    git clone https://git.openstack.org/openstack/kolla

    # Install Kolla
    pushd kolla
    sudo pip install --editable .
    sudo ln -sf `readlink -f ./etc/kolla` /etc/  # link from hard-coded kolla path
    popd

    # Generate Kolla Configuration Files
    pushd kolla
    ./tools/generate_passwords.py
    sudo ./tools/kolla-ansible genconfig
    popd

    # Clone Kolla-Kubernetes
    git clone https://git.openstack.org/openstack/kolla-kubernetes

    # Install Kolla-Kubernetes
    pushd kolla-kubernetes
    sudo pip install --editable .
    popd


Notes:

- Ansible commands (e.g. kolla-ansible) targeting the local machine require
  sudo because ansible creates /etc/.ansible_* files.
- Executing local versions of kolla tools ```./tools/kolla-ansible``` instead
  of from the system path, will locate resource files from relative locations
  instead of system locations.
- The development install will also work with Python virtual environments.


Building Kolla Containers
=========================

Kolla-kubernetes works against Kolla mainline's containers but it is the
expected behavior that you build them locally.

The Kolla documentation engine has a detailed `overview of building the
containers <http://docs.openstack.org/developer/kolla/image-building.html>`_.

The brief summary is as follows::

    pushd kolla
    ./tools/build.py mariadb
    ./tools/build.py memcached
    ./tools/build.py kolla-toolbox
    ./tools/build.py keystone
    ./tools/build.py horizon
    # ... <and so on>
    popd


Running Kolla-Kubernetes
========================

The following commands will allow you to bootstrap a running Horizon instance,
including all of its dependencies.  Some kolla containers require
bootstrapping, while others do not.::

    kolla-kubernetes bootstrap mariadb
    kolla-kubernetes run mariadb
    kolla-kubernetes run memcached
    kolla-kubernetes bootstrap keystone
    kolla-kubernetes run keystone
    kolla-kubernetes run horizon

