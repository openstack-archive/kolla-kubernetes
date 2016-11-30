.. development_environment:

==========================================
Kolla Kubernetes Dev Environment
==========================================

Install Vagrant
================

Currently, a Vagrant version <1.9.0 is required.

Either from https://www.vagrantup.com/
or if you are on Linux with libvirt, via the following instructions:

## CentOS 7.2

::
    # Install vagrant:
    sudo yum install -y https://releases.hashicorp.com/vagrant/1.8.1/vagrant_1.8.1_x86_64.rpm

    # Now lets install the deps for vagrant libvirt and ensure git is present:
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

    #Now we can install the libvirt plugin itself
    vagrant plugin install vagrant-libvirt

    #Now setup libvirt access for your current user
    sudo bash -c 'cat << EOF > /etc/polkit-1/rules.d/80-libvirt-manage.rules
    polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" && subject.local && subject.active && subject.isInGroup("wheel")) {
      return polkit.Result.YES;
    }
    });
    EOF'
    sudo usermod -aG libvirt $USER

    # Start and enable libvirt
    sudo systemctl start libvirtd
    sudo systemctl enable libvirtd
    
    # The last step is to install ansible
    sudo yum install -y epel-release
    sudo yum install -y ansible

Finally before continuing log out and back in again for your session to have the
correct permissions applied

## Ubuntu 16.04

::
    # Install vagrant:
    sudo apt-get update
    # Note that theres is a packaging bug in ubuntu so the upstream package must
    # be used: https://github.com/vagrant-libvirt/vagrant-libvirt/issues/575
    curl -L https://releases.hashicorp.com/vagrant/1.8.1/vagrant_1.8.1_x86_64.deb > /tmp/vagrant_1.8.1_x86_64.deb
    sudo apt-get -y install /tmp/vagrant_1.8.1_x86_64.deb

    # Now lets install the deps for vagrant libvirt:
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
                 git-review

    # Now we can install the libvirt plugin itself
    vagrant plugin install vagrant-libvirt

    # Now setup libvirt access for your current user
    sudo adduser $USER libvirtd
    
    # The last step is to install ansible >2.2
    sudo apt-get install -y software-properties-common
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

Finally before continuing log out and back in again for your session to have the
correct permissions applied


## MacOS

Install the CLI Developer tools by running the following in a terminal:

::
    xcode-select --install

Download and install VirtualBox from:
 * https://www.virtualbox.org/wiki/Downloads
 
Download and install vagrant using the following url to obtain the package:
 * https://releases.hashicorp.com/vagrant/1.8.7/vagrant_1.8.7.dmg
There is a bug in Vagrant 1.8.7's embedded curl that prevents boxes being
downloaded, as described in: https://github.com/mitchellh/vagrant/issues/7997.
This can be resolved by running the following command:

::
    sudo rm -f /opt/vagrant/embedded/bin/curl

Download and install git from:
 * https://git-scm.com/download/mac

Now we can install ansible:
::
    easy_install --user pip
    printf 'if [ -f ~/.bashrc ]; then\n  source ~/.bashrc\nfi\n' >> $HOME/.profile
    printf 'export PATH=$PATH:$HOME/Library/Python/2.7/bin\n' >> $HOME/.bashrc
    source $HOME/.profile
    pip install --user --upgrade ansible
    sudo mkdir /etc/ansible
    sudo curl -L https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg -o /etc/ansible/ansible.cfg

Under MacOS, you may encounter an error during ```vagrant up``` later on, this
can be resolved by running ```ulimit -n 4048``` from the CLI before bringing the
environment up.    

Obtain sources for building the environment
===========================

The dev environment requires you to clone two git repo's

::

    git clone https://github.com/att-comdev/halcyon-vagrant-kubernetes
    git clone https://github.com/portdirect/halcyon-kubernetes


Setup environment
===========================

Move into the ```halcyon-vagrant-kubernetes``` directory and edit the
```config.rb``` file to meet your reqirements:

::


    # Kubernetes Details: Instances
    $kube_version      = "centos/7"
    $kube_memory       = 4096
    $kube_vcpus        = 2
    $kube_count        = 4
    $git_commit        = "6a7308d"
    $subnet            = "192.168.236"
    $public_iface      = "eth1"
    $forwarded_ports   = {}

    # Ansible Declarations:
    #$number_etcd       = "kube[1:2]"
    #$number_master     = "kube[1:2]"
    #$number_worker     = "kube[1:3]"
    $kube_masters      = "kube1"
    $kube_workers      = "kube[2:4]"
    $kube_control      = "kube1"

    # Virtualbox leave / Openstack change to OS default username:
    $ssh_user          = "centos"
    $ssh_keypath       = "~/.ssh/id_rsa"
    $ssh_port          = 22

    # Ansible Details:
    $ansible_limit     = "all"
    $ansible_playbook  = "../halcyon-kubernetes/kube-deploy/kube-deploy.yml"
    $ansible_inventory = ".vagrant/provisioners/ansible/inventory_override"

    # Openstack Authentication Information:
    $os_auth_url       = "http://your.openstack.url:5000/v2.0"
    $os_username       = "user"
    $os_password       = "password"
    $os_tenant         = "tenant"

    # Openstack Instance Information:
    $os_flavor         = "m1.small"
    $os_image          = "centos-7.2"
    $os_floatnet       = "public"
    $os_fixednet       = ['vagrant-net']
    $os_keypair        = "your_ssh_keypair"
    $os_secgroups      = ["default"]

    # Proxy Configuration (only use if deploying behind a proxy):
    $proxy_enable      = false
    $proxy_http        = "http://proxy:8080"
    $proxy_https       = "https://proxy:8080"
    $proxy_no          = "localhost,127.0.0.1"

When editing this file you can change ```$ansible_playbook``` to point to the
dir containing the halcyon-kubernetes repo. You can also adjust the number of
kube workers (note that the first node will only run k8s pods by default), but
you will then need to adjust ```$kube_workers``` accordingly


Managing and interacting with the environment
===========================

Now you can run:
 - ```vagrant up``` to create a kube cluster, running under CentOS, with romana
   CNI networking, Ceph clients installed and helm
 - ```vagrant destroy``` to make it all go away.
 - ```./get-k8s-creds.sh``` to get the k8s credentials for the cluster and setup
   kubectl on your host to access it. If you have helm installed on your
   host[2], you can then run ```helm init``` on your local machine and should be
   able to work outside of the cluster if desired.
 - ```vagrant ssh kube1``` to ssh into the master node

Note that it will take a few minutes for everything to be operational, typically
between 2-5 mins after vagrant/ansible has finished for all services to be
online for my machine (Xeon E3-1240 v3, 32GB, SSD), primarily dependant on
network performance. This is as it takes time for the images to be pulled, and
CNI networking to come up, DNS being usually the last service to become active.


Testing the deployed environment
===========================

You can test that everything is working by running:
```
kubectl run -i -t $(uuidgen) --image=busybox --restart=Never
```
and then once inside the container:
```
nslookup kubernetes
```

To test that helm is working you can run the following:
```
helm init --client-only
helm repo update
helm install stable/mysql
helm ls
# and to check via kubectl
kubectl get all
```
The pods will not provision, in this example and be shown as pending as there is
no dynamic PVC creation within the cluster *yet*.


Setting up kubernetes for kolla-k8s deployment
===========================

To set the cluster up for developing kolla-k8s: you will most likely want to run
the following command:
```
kubectl get nodes -L kubeadm.alpha.kubernetes.io/role --no-headers | awk '$NF ~ /^<none>/ { print $1}' | while read NODE ; do
kubectl label node $NODE --overwrite kolla_controller=true
kubectl label node $NODE --overwrite kolla_compute=true
done
```
This will mark all the workers as being available for both storage and API pods.

