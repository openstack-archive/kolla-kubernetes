.. setup-host:

=================================
Kolla Kubernetes Host Setup Guide
=================================

Dependencies
============

=====================   ===========  ===========  =========================
Component               Min Version  Max Version  Comment
=====================   ===========  ===========  =========================
Ansible                 2.00         none         On deployment host
Docker                  1.10         none         On target nodes
Docker Python           1.6.0        none         On target nodes
Python Jinja2           2.8.0        none         On deployment host
Kubernetes              1.3.0        none         On all hosts
=====================   ===========  ===========  =========================

.. NOTE:: Kolla (which provides the templating) is sensitive about the
  Ansible version.  Mainline currently requires 2.0.x or above.

Installing Docker
=================

Since Docker is required to build images as well as be present on all deployed
targets, the kolla-kubernetes community recommends installing the official
Docker, Inc. packaged version of Docker for maximum stability and compatibility.

.. NOTE:: Docker 1.11.0 is not compatible with Kubernetes due to some issues in
  Docker.

::

    # Install Docker
    curl -sSL https://get.docker.io | bash

Docker has to run with ``shared`` mounts instead of ``slave`` mounts in order
for Neutron namespaces to be shared amoung the host and the containers.

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

Installing Kolla and Kolla-Kubernetes
=====================================

Kolla-kubernetes depends on configuration files (and images) that are generated
from kolla.  When fully installed, kolla default configuration files
(globals.yml) are expected in ``/etc/kolla`` (globals.yml).  Newly generated
configuration files are placed in the same directory.  Kolla's
``generate_passwords.py`` creates a passwords.yml file which contains passwords
and encryption keys.  Kolla's ``kolla-ansible genconfig`` will generate the
config files for each kolla service container based on the contents of
globals.yml and passwords.yml

::

    git clone https://git.openstack.org/openstack/kolla
    sudo cp -r ./etc/kolla /etc

    # Clone Kolla-Kubernetes
    git clone https://git.openstack.org/openstack/kolla-kubernetes

    # Install Kolla-Kubernetes
    sudo pip install -e kolla-kubernetes/
    sudo cp -r kolla-kubernetes/etc/kolla-kubernetes /etc

Generate Config Files
=====================

Edit the file ``/etc/kolla/globals.yml`` to add these settings which
are specific to kolla-kubernetes:

::

    # Kolla-kubernetes custom configuration
    orchestration_engine: "KUBERNETES"
    api_interface_address: "0.0.0.0"
    memcached_servers: "memcached"
    keystone_database_address: "mariadb"
    keystone_admin_url: "http://keystone-admin:35357/v3"
    keystone_internal_url: "http://keystone-public:5000/v3"
    keystone_public_url: "http://keystone-public:5000/v3"
    glance_registry_host: "glance"

Then, generate the Kolla configuration files:

::

    ./kolla/tools/generate_passwords.py
    ./kolla/tools/kolla-ansible genconfig

Building Kolla Containers
=========================

Build kolla's containers locally to have the latest containers.

The Kolla documentation engine has a detailed `overview of building the
containers <http://docs.openstack.org/developer/kolla/image-building.html>`_.

::
    ./kolla/tools/build.py mariadb memcached kolla-toolbox keystone horizon nova neutron
