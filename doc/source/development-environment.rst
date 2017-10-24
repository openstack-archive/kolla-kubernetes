.. development_environment:

==========================================
Kolla Kubernetes Development Environment
==========================================

.. warning::

   The development environment guide is outdated.  It no longer
   works with Kubernetes master.  We are debating what to do about that
   but until that time, please use the deployment guide for development.

Overview
========

The kolla-kubernetes development environment is intended to run on a dedicated
development machine such as a workstation or laptop. This development
environment is not intended to run on a virtual machine although that
is feasible.  Following this guide will have a minimal impact to the host
operating system. Some software and libraries will be installed and some
configuration changes will be required.

Install Vagrant and Ansible
===========================

You can use Halcyon-Vagrant-Kubernetes with the VirtualBox, Libvirt or OpenStack
vagrant providers. The documentation here describes the Libvirt provider for
Linux hosts, but VirtualBox is perfectly acceptable as well if preferred. For
more information about Halcyon-Kubernetes, please refer to the Github
repositories:

* https://github.com/att-comdev/halcyon-vagrant-kubernetes (Vagrant components)

* https://github.com/att-comdev/halcyon-kubernetes (Ansible Playbooks)


.. note::

   Currently, the following versions are tested and required:
     * ansible >= 2.2.0
     * helm >= 2.2.0
     * kubernetes >= 1.5.2
     * vagrant <1.9.0



.. note::

   The official Ubuntu image is currently incompatible with the vagrant-libvirt
   provider, but works without issues using either the VirtualBox or OpenStack
   providers.


CentOS 7.2 with Libvirt
-----------------------

Firstly install Vagrant:

.. path .
.. code-block:: console

    sudo yum install -y \
         https://releases.hashicorp.com/vagrant/1.8.1/vagrant_1.8.1_x86_64.rpm

.. end

Then install the deps for vagrant libvirt and ensure git-review is present:

.. path .
.. code-block:: console

    sudo yum install -y libvirt \
                        libxslt-devel \
                        libxml2-devel \
                        libvirt-devel \
                        libguestfs-tools-c \
                        ruby-devel \
                        gcc \
                        git \
                        git-review \
                        gcc-c++

.. end

Now we can install the libvirt plugin itself:

.. path .
.. code-block:: console

    vagrant plugin install vagrant-libvirt

.. end

Now you can setup Libvirt for use without requiring root privileges:

.. path .
.. code-block:: console

    sudo bash -c 'cat << EOF > /etc/polkit-1/rules.d/80-libvirt-manage.rules
    polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" && subject.local && subject.active && subject.isInGroup("wheel")) {
      return polkit.Result.YES;
    }
    });
    EOF'

    sudo usermod -aG libvirt $USER

.. end

Once both Libvirt and Vagrant have been prepared, you should now start and enable Libvirt:

.. path .
.. code-block:: console

    sudo systemctl start libvirtd
    sudo systemctl enable libvirtd

.. end

Finally install Ansible to allow Halcyon Kubernetes to provision the cluster:

.. path .
.. code-block:: console

    sudo yum install -y epel-release
    sudo yum install -y ansible

.. end

Before continuing, log out and back in again for your session to have the correct
permissions applied.


Ubuntu 16.04 with Libvirt
-------------------------

Firstly install Vagrant:

.. path .
.. code-block:: console

    sudo apt-get update
    # Note that theres is a packaging bug in ubuntu so the upstream package must
    # be used: https://github.com/vagrant-libvirt/vagrant-libvirt/issues/575
    curl -L https://releases.hashicorp.com/vagrant/1.8.1/vagrant_1.8.1_x86_64.deb > /tmp/vagrant_1.8.1_x86_64.deb
    sudo apt-get -y install /tmp/vagrant_1.8.1_x86_64.deb

.. end

Then install the dependencies for vagrant-libvirt and ensure git-review is present:

.. path .
.. code-block:: console

    sudo sed -i 's/^# deb-src/deb-src/g' /etc/apt/sources.list
    sudo apt-get update
    sudo apt-get -y build-dep vagrant ruby-libvirt
    sudo apt-get install -y \
                 qemu-kvm \
                 libvirt-bin \
                 ebtables \
                 dnsmasq \
                 libxslt-dev \
                 libxml2-dev \
                 libvirt-dev \
                 zlib1g-dev \
                 ruby-dev \
                 git \
                 git-review \
                 g++ \
                 qemu-utils

.. end

Now we can install the libvirt plugin itself:

.. path .
.. code-block:: console

    vagrant plugin install vagrant-libvirt

.. end

Now you can setup Libvirt for use without requiring root privileges:

.. path .
.. code-block:: console

    sudo adduser $USER libvirtd

.. end

Finally, install Ansible to allow Halcyon Kubernetes to provision the cluster:

.. path .
.. code-block:: console

    sudo apt-get install -y software-properties-common
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

.. end

Before continuing, log out and back in again for your session to have the correct
permissions applied.


MacOS
----------

Install the CLI Developer tools by opening a terminal and running:

.. path .
.. code-block:: console

    xcode-select --install

.. end

Download and install VirtualBox from:
 * https://www.virtualbox.org/wiki/Downloads

Download and install vagrant using the following url to obtain the package:
 * https://releases.hashicorp.com/vagrant/1.8.7/vagrant_1.8.7.dmg
There is a bug in Vagrant 1.8.7's embedded curl that prevents boxes being
downloaded, as described in: https://github.com/mitchellh/vagrant/issues/7997.
This can be resolved by running the following command:

.. path .
.. code-block:: console

    sudo rm -f /opt/vagrant/embedded/bin/curl

.. end


If your version of MacOS doesn't not include git in the CLI Developer tools
installed above, you can download and install git from:
 * https://git-scm.com/download/mac

Now we can install Ansible:

.. path .
.. code-block:: console

    easy_install --user pip
    printf 'if [ -f ~/.bashrc ]; then\n  source ~/.bashrc\nfi\n' >> $HOME/.profile
    printf 'export PATH=$PATH:$HOME/Library/Python/2.7/bin\n' >> $HOME/.bashrc
    source $HOME/.profile
    pip install --user --upgrade ansible
    sudo mkdir /etc/ansible
    sudo curl -L https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg -o /etc/ansible/ansible.cfg

.. end



.. note::

   Under MacOS, you may encounter an error during ``vagrant up``, complaining
   that too many files are open. This is as recent versions of MacOS limit the
   number of file descriptors per application to 200. A simple way to resolve
   this is by running ``ulimit -n 4048`` from the CLI before bringing the
   environment up.

Install Kubernetes and Helm clients
===================================

To complete the development environment setup, it is mandatory to have
both a kubernetes client (kubectl) and a helm client (helm) installed on
the host operating system.

Installing Clients on CentOS or Ubuntu
--------------------------------------

To install the kubernetes clients:

.. code-block:: console

    curl -L https://dl.k8s.io/v1.5.2/kubernetes-client-linux-amd64.tar.gz | tar -xzv
    sudo cp kubernetes/client/bin/* /usr/local/bin
    sudo chmod 755 /usr/local/bin/kubefed /usr/local/bin/kubectl
    sudo chown root: /usr/local/bin/kubefed /usr/local/bin/kubectl

.. end

To install the helm client:

.. code-block:: console

    curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.2.2-linux-amd64.tar.gz | tar -xzv
    sudo cp linux-amd64/helm /usr/local/bin/helm
    sudo chmod 755 /usr/local/bin/helm
    sudo chown root: /usr/local/bin/helm

.. end

Installing Clients on MacOS
---------------------------

To install the kubernetes clients:

.. code-block:: console

    curl -L https://dl.k8s.io/v1.5.2/kubernetes-client-darwin-amd64.tar.gz | tar -xzv
    sudo cp kubernetes/client/bin/* /usr/local/bin
    sudo chmod 755 /usr/local/bin/kubefed /usr/local/bin/kubectl
    sudo chown root: /usr/local/bin/kubefed /usr/local/bin/kubectl

.. end

To install the helm client:

.. code-block:: console

    curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.2.2-darwin-amd64.tar.gz | tar -xzv
    sudo cp darwin-amd64/helm /usr/local/bin/helm
    sudo chmod 755 /usr/local/bin/helm
    sudo chown root: /usr/local/bin/helm

.. end

Setup environment
=================

Clone the repo containing the dev environment:

.. path .
.. code-block:: console

    git clone https://github.com/att-comdev/halcyon-vagrant-kubernetes

.. end


Initialize the ```halcyon-vagrant-kubernetes``` repository:

.. path .
.. code-block:: console

    cd halcyon-vagrant-kubernetes
    git submodule init
    git submodule update

.. end

You can then setup Halcyon Vagrant for Kolla. You can select either ``centos``
or ``ubuntu`` as a guest operating system though currently Ubuntu is only
supported by the Vagrant VirtualBox and OpenStack providers.

.. path .
.. code-block:: console

    ./setup-halcyon.sh \
        --k8s-config kolla \
        --k8s-version v1.5.2 \
        --guest-os centos

.. end


.. note::

   If you need to use a proxy then you should also edit the ``config.rb`` file
   as follows:
    * Set ``proxy_enable = true``
    * Set ``proxy_http`` and ``proxy_https`` values for your proxy
    * Configure ``proxy_no`` as appropriate. ``proxy_no`` should also include
      the ip's of all kube cluster members.
      (i.e. 172.16.35.11,172.16.35.12,172.16.35.13,172.16.35.14)
    * Edit the no_proxy environment variable on your host to include the kube
      master IP (172.16.35.11)


Managing and interacting with the environment
=============================================

The kube2 system in your halcyon-vagrant environment should have a minimum
of 4gb of ram and all others should be set to 2gb of ram.  In your
config.rb script kube_vcpus should be set to 2 and kube_count should be
set to 4.

Once the environment's dependencies have been resolved and configuration
completed, you can run the following commands to interact with it:

.. path .
.. code-block:: console

    vagrant up         # To create and start your halcyon-kubernetes cluster.
                       # You can also use --provider=libvirt

    ./get-k8s-creds.sh # To get the k8s credentials for the cluster and setup
                       # kubectl on your host to access it, if you have the helm
                       # client installed on your host this script will also set
                       # up the client to enable you to perform all development
                       # outside of the cluster.

   vagrant ssh kube1   # To ssh into the master node.

   vagrant destroy     # To make it all go away.


.. end


Note that it will take a few minutes for everything to be operational, typically
between 2-5 mins after vagrant/ansible has finished for all services to be
online for my machine (Xeon E3-1240 v3, 32GB, SSD), primarily dependent on
network performance. This is as it takes time for the images to be pulled, and
CNI networking to come up, DNS being usually the last service to become active.


Testing the deployed environment
================================

Test everything works by starting a container with an interactive terminal:

.. path .
.. code-block:: console

    kubectl run -i -t $(uuidgen) --image=busybox --restart=Never

.. end

Once that pod has started and your terminal has connected to it, you can then
test the Kubernetes DNS service (and by extension the CNI SDN layer) by running:

.. path .
.. code-block:: console

    nslookup kubernetes

.. end

To test that helm is working you can run the following:

.. path .
.. code-block:: console

    helm init --client-only
    helm repo update
    helm install stable/memcached --name helm-test
    # check the deployment has succeeded
    helm ls
    # and to check via kubectl
    kubectl get all
    # and finally remove the test memcached chart
    helm delete helm-test --purge

.. end

.. note::

    If you receive the error ```Error: could not find a ready tiller pod```
    helm is likely pulling the image to the kubernetes cluster.  This error
    may also be returned if you have a proxy server environment and the
    development environment is not setup properly for the proxy server.


Containerized development environment requirements and usage
=====================================================

Make sure to run the ./get-k8s-creds.sh script or the development environment
container will not be able to connect to the vagrant kubernetes cluster.

The kolla-kubernetes and kolla-ansible project should be checked out into
the same base directory as halcyon-vagrant-kubernetes.  The default assumed
in kolla-kubernetes/tools/build_dev_image.sh is ~/devel.  If that is not the
case in your environment then set the environment variable dev_path to the
path appropriate for you.

.. path .
.. code-block:: console

    git clone https://github.com/openstack/kolla-kubernetes.git
    git clone https://github.com/openstack/kolla-ansible.git

    # Set dev_path environment variable to match your development base dir

    kolla-kubernetes/tools/build_dev_image.sh
    kolla-kubernetes/tools/run_dev_image.sh

.. end
