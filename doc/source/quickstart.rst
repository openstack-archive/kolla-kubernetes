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

Installing Docker
=================

Since Docker is required to build images as well as be present on all deployed
targets, the kolla-kubernetes community recommends installing the official
Docker, Inc. packaged version of Docker for maximum stability and compatibility.

.. NOTE:: Docker 1.11.0 is not compatible with Kubernetes due to some issues in
  Docker. The below command will install the latest docker and revert back to
  1.10.3.  For different Debian or Ubuntu distributions, you may need to use
  ``apt-cache madison docker-engine`` to get the correct version.

::

    # Install Docker
    curl -sSL https://get.docker.io | bash

    # CentOS
    sudo yum downgrade -y docker-engine-1.10.3-1.el7.centos

    # Ubuntu (Assuming "Trusty Tahr" 14.04 LTS)
    sudo apt-get -y remove docker-engine
    sudo apt-get -y install docker-engine=1.10.3-0~trusty

Docker needs to run with the root filesystem as shared in order for
HyperKube to run and Neutron to function in 'thin' containers.

For CentOS and other systemd distros, change MountFlags from "slave"
to "shared" and restart Docker.

::

   # CentOS (and other systemd distros)
   # Edit /usr/lib/system/systemd/docker.service to set:
   MountFlags=shared

   # Restart the Docker daemon
   systemctl daemon-reload
   systemctl start docker

For Ubuntu 14.04 LTS, add a command to /etc/rc.local to mark the root
filesystem as shared upon startup.

::

   # Ubuntu (and other non-systemd distros)
   # Edit /etc/rc.local to add:
   mount --make-shared /

   # Ensure the mount is shared
   sudo sh /etc/rc.local


For Ubuntu 14.04 LTS, configure the Docker daemon to use the DeviceMapper
`Storage Backend <http://www.projectatomic.io/docs/filesystems>`_ instead of
AUFS due to `this bug
<https://github.com/docker/docker/issues/8966#issuecomment-94210446>`_.
Without this modification, it would not be possible to run the Kolla-built
CentOS docker images since they are created with an older version of AUFS.
Therefore, use a different Storage Backend than AUFS.

::

   # Ubuntu
   # Edit /etc/default/docker to add:
   DOCKER_OPTS="-s devicemapper"

   # Restart the Docker daemon
   sudo service docker stop
   sudo service docker start


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

    # Clone Kolla-Kubernetes
    git clone https://git.openstack.org/openstack/kolla-kubernetes

    # Install Kolla-Kubernetes
    pushd kolla-kubernetes
    sudo pip install --editable .
    popd


.. NOTE::
  - Ansible commands (e.g. kolla-ansible) targeting the local machine require
    sudo because ansible creates ```/etc/.ansible_*``` and
    ```/etc/kolla/<service>``` files which require root permissions.
  - Executing local versions of kolla tools ```./tools/kolla-ansible``` instead
    of from the system path, will locate resource files from relative locations
    instead of system locations.
  - The development install will also work with Python virtual environments.


Configure Kolla-Kubernetes
==========================

Edit the file ```/etc/kolla/globals.yml``` to add these settings which
are specific to kolla-kubernetes:

::

    # Kolla-kubernetes custom configuration
    api_interface_address: "0.0.0.0"
    memcached_servers: "memcached"
    keystone_database_address: "mariadb"
    keystone_admin_url: "http://keystone-admin:35357/v3"
    keystone_internal_url: "http://keystone-public:5000/v3"
    keystone_public_url: "http://keystone-public:5000/v3"


Then, generate the Kolla configuration files:

::

    # Generate Kolla Configuration Files
    pushd kolla
    sudo ./tools/generate_passwords.py
    sudo ./tools/kolla-ansible genconfig
    popd


Building Kolla Containers
=========================

Kolla-kubernetes works against Kolla mainline's containers but it is the
expected behavior that you build them locally.

The Kolla documentation engine has a detailed `overview of building the
containers <http://docs.openstack.org/developer/kolla/image-building.html>`_.

The brief summary for horizon kolla dependencies is as follows::

    kolla-build mariadb memcached kolla-toolbox keystone horizon


Running Kolla-Kubernetes
========================

The following commands will allow you to bootstrap a running Horizon instance,
including all of its ordered dependencies.  Some kolla containers require
bootstrapping, while others do not.::

    kolla-kubernetes bootstrap mariadb
    kolla-kubernetes run mariadb
    kolla-kubernetes run memcached
    kolla-kubernetes bootstrap keystone
    kolla-kubernetes run keystone
    kolla-kubernetes run horizon

A similar pattern may be followed for Openstack services beyond horizon.
