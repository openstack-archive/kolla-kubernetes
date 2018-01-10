#!/usr/bin/env python

# Copyright 2017-present, Lenovo
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

'''
ko.py - Kolla Kubernetes Openstack deployer

Purpose
=======

This is a tool to deploy OpenStack on a Kubernetes Cluster using Kolla images
and Kolla-Kubernetes on bare metal servers or virtual machines.

It sticks to the methods outlined in the kolla-kubernetes Bare Metal
Deployment Guide:

https://docs.openstack.org/developer/kolla-kubernetes/deployment-guide.html

This tool exists primarily to:

1. Provide an easy way to run kolla-kubernetes which is a development project
to deploy Kolla OpenStack images on a Kubernetes Cluster.

2. Ease development of kolla-kubernetes.

3. Provide an OpenStack environment that is Production Level.

Features
========
1. Supports both Centos and Ubuntu natively.

2. Requires just a VM with two NIC's, low congnitive overhead:
'ko.py int1 int2'.

4. Options to change the versions of all the tools, like helm, kubernetes etc.

5. Options to change the image version (openstack release) and image tag
(micro-version) of OpenStack as needed. The user can quickly play with Ocata,
or Pike or Master(Queens).

6. Easy on the eye output, with optional verbose mode for more information.

7. Contains a demo mode that walks the user through each step with additional
information and instruction.

8. Verifies its completeness by generating a VM in the OpenStack Cluster.

9. Leaves the user with a working OpenStack Cluster with all the basic
services.

10. Lots of options to customize - even edit globals.yaml and cloud.yaml before
deploying.

11. Cleans up previous deployment with --cc option

12. Select a different docker registry to the default (kolla) to run with
custom images.

13. Select between Canal and Weave CNI's for inter-pod communications.

14. Optionally installs a fluent-bit container for log aggregation to ELK.

15. Option to create a kubernetes minion to add to existing deployment.

16. Option to create a kubernetes cluster only - no OpenStack - but another
option to install OpenStack over an existing Kubernetes cluster.

17. Option to not overwrite kolla-kubenetes directory for development of
kolla-kubernetes code.

Host machine requirements
=========================

The host machine must satisfy the following minimum requirements:

- 2 network interfaces
- 8GB min, 16GB preferred RAM
- 40G min, 80GB preferred disk space
- 2 CPU's Min, 4 preferred CPU's
- Root access to the deployment host machine

Prerequisites
=============

Verify the state of network interfaces. If using a VM spawned on OpenStack as
the host machine, the state of the second interface will be DOWN on booting
the VM.

    ip addr show

Bring up the second network interface if it is down.

    ip link set ens4 up

However as this interface will be used for Neutron External, this Interface
should not have an IP Address. Verify this with.

    ip addr show


Mandatory Inputs
================

1. mgmt_int (network_interface):
Name of the interface to be used for management operations.

The `network_interface` variable is the interface to which Kolla binds API
services. For example, when starting Mariadb, it will bind to the IP on the
interface list in the ``network_interface`` variable.

2. neutron_int (neutron_external_interface):
Name of the interface to be used for Neutron operations.

The `neutron_external_interface` variable is the interface that will be used
for the external bridge in Neutron. Without this bridge the deployment instance
traffic will be unable to access the rest of the Internet.

To create two interfaces like this in Ubuntu, for example:

Edit /etc/network/interfaces:

# The primary network interface
auto ens3
iface ens3 inet dhcp

# Neutron network interface (up but no ip address)
auto ens4
iface ens4 inet manual
ifconfig ens4 up

TODO
====

1. Convert to using https://github.com/kubernetes-incubator/client-python
2. Note there are various todo's scattered inline as well.

Recomendations
==============
1. Due to the length the script can run for, recomend disabling sudo timeout:

sudo visudo
Add: 'Defaults    timestamp_timeout=-1'

2. Due to the length of time the script can run for, I recommend using nohup

E.g. nohup python -u k8s.py eth0 eth1

Then in another window:

tail -f nohup.out

3. Can be run remotely with:

curl https://raw.githubusercontent.com/RichWellum/k8s/master/ko.py \
| python - ens3 ens4 --image_version master -cni weave
'''

from __future__ import print_function
import argparse
from argparse import RawDescriptionHelpFormatter
import logging
import os
import platform
import random
import re
import subprocess
import sys
import tarfile
import time


logger = logging.getLogger(__name__)

# Nasty globals but used universally
global PROGRESS
PROGRESS = 0

global K8S_FINAL_PROGRESS
K8S_FINAL_PROGRESS = 0

# Set these both to 0 as they get set later depending on what is configured
global KOLLA_FINAL_PROGRESS
KOLLA_FINAL_PROGRESS = 0

global K8S_CLEANUP_PROGRESS
K8S_CLEANUP_PROGRESS = 0


def set_logging():
    '''Set basic logging format.'''

    FORMAT = "[%(asctime)s.%(msecs)03d %(levelname)8s: "\
        "%(funcName)20s:%(lineno)s] %(message)s"
    logging.basicConfig(format=FORMAT, datefmt="%H:%M:%S")


class AbortScriptException(Exception):
    '''Abort the script and clean up before exiting.'''


def parse_args():
    '''Parse sys.argv and return args'''

    parser = argparse.ArgumentParser(
        formatter_class=RawDescriptionHelpFormatter,
        description='This tool provides a method to deploy OpenStack on a '
        'Kubernetes Cluster using Kolla\nand Kolla-Kubernetes on bare metal '
        'servers or virtual machines.\nVirtual machines supported are Ubuntu '
        'and Centos. \nUsage as simple as: "ko.py eth0 eth1"\n'
        'The host machine must satisfy the following minimum requirements:\n'
        '- 2 network interfaces\n'
        '- 8GB min, 16GB preferred - main memory\n'
        '- 40G min, 80GB preferred - disk space\n'
        '- 2 CPUs Min, 4 preferred - CPUs\n'
        'Root access to the deployment host machine is required.',
        epilog='E.g.: ko.py eth0 eth1 -iv master -cni weave --logs\n')
    parser.add_argument('MGMT_INT',
                        help='The interface to which Kolla binds '
                        'API services, E.g: eth0')
    parser.add_argument('NEUTRON_INT',
                        help='The interface that will be used for the '
                        'external bridge in Neutron, E.g: eth1')
    parser.add_argument('-mi', '--mgmt_ip', type=str, default='None',
                        help='Provide own MGMT ip address Address, '
                        'E.g: 10.240.83.111')
    parser.add_argument('-vi', '--vip_ip', type=str, default='None',
                        help='Provide own Keepalived VIP, used with '
                        'keepalived, should be an unused IP on management '
                        'NIC subnet, E.g: 10.240.83.112')
    parser.add_argument('-iv', '--image_version', type=str, default='ocata',
                        help='Specify a different Kolla image version to '
                        'the default (ocata)')
    parser.add_argument('-it', '--image_tag', type=str,
                        help='Specify a different Kolla tag version to '
                        'the default which is the same as the image_version '
                        'by default')
    parser.add_argument('-hv', '--helm_version', type=str, default='2.7.2',
                        help='Specify a different helm version to the '
                        'default(2.7.2)')
    parser.add_argument('-kv', '--k8s_version', type=str, default='1.9.1',
                        help='Specify a different kubernetes version to '
                        'the default(1.9.1) - note 1.8.0 is the minimum '
                        'supported')
    parser.add_argument('-av', '--ansible_version', type=str,
                        default='2.4.2.0',
                        help='Specify a different ansible version to '
                        'the default(2.4.2.0)')
    parser.add_argument('-jv', '--jinja2_version', type=str, default='2.10',
                        help='Specify a different jinja2 version to '
                        'the default(2.10)')
    parser.add_argument('-dr', '--docker_repo', type=str, default='kolla',
                        help='Specify a different docker repo from '
                        'the default(kolla), for example "rwellum" has '
                        'the latest pike images')
    parser.add_argument('-cni', '--cni', type=str, default='canal',
                        help='Specify a different CNI/SDN to '
                        'the default(canal), like "weave"')
    parser.add_argument('-l', '--logs', action='store_true',
                        help='Install fluent-bit container')
    parser.add_argument('-k8s', '--kubernetes', action='store_true',
                        help='Stop after bringing up kubernetes, '
                        'do not install OpenStack')
    parser.add_argument('-cm', '--create_minion', action='store_true',
                        help='Do not install Kubernetes or OpenStack, '
                        'useful for preparing a multi-node minion')
    parser.add_argument('-os', '--openstack', action='store_true',
                        help='Build OpenStack on an existing '
                        'Kubernetes Cluster')
    parser.add_argument('-eg', '--edit_globals', action='store_true',
                        help='Pause to allow the user to edit the '
                        'globals.yaml file - for custom configuration')
    parser.add_argument('-ec', '--edit_cloud', action='store_true',
                        help='Pause to allow the user to edit the '
                        'cloud.yaml file - for custom configuration')
    parser.add_argument('-v', '--verbose', action='store_const',
                        const=logging.DEBUG, default=logging.INFO,
                        help='Turn on verbose messages')
    parser.add_argument('-d', '--demo', action='store_true',
                        help='Display some demo information and '
                        'offer to move on')
    parser.add_argument('-f', '--force', action='store_true',
                        help='When used in conjunction with --demo - it '
                        'will proceed without user input.')
    parser.add_argument('-nn', '--no_network', action='store_true',
                        help='Do not try to create a OpenStack network model, '
                        'configure neutron, download and install a test VM')
    parser.add_argument('-dm', '--dev_mode', action='store_true',
                        help='Adds option to modify kolla and more info')
    parser.add_argument('-ng', '--no_git', action='store_true',
                        help='Select this to not override git repos '
                        'previously downloaded')
    parser.add_argument('-bd', '--base_distro', type=str, default='centos',
                        help='Specify a base container image to '
                        'the default(centos), like "ubuntu"')
    parser.add_argument('-c', '--cleanup', action='store_true',
                        help='YMMV: Cleanup existing Kubernetes cluster '
                        'before creating a new one. Because LVM is not '
                        'cleaned up, space will be used up. '
                        '"-cc" is far more reliable but requires a reboot')
    parser.add_argument('-cc', '--complete_cleanup', action='store_true',
                        help='Cleanup existing Kubernetes cluster '
                        'then exit, rebooting host is advised')

    return parser.parse_args()


def run_shell(args, cmd):
    '''Run a shell command and return the output

    Print the output and errors if debug is enabled
    Not using logger.debug as a bit noisy for this info
    '''

    p = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        shell=True)
    out, err = p.communicate()

    if args.demo:
        if not re.search('kubectl get pods', cmd):
            print('DEMO: CMD: "%s"' % cmd)

    out = out.rstrip()
    err = err.rstrip()

    if args.verbose == 10:  # Hack - debug enabled
        if str(out) is not '0' and str(out) is not '1' and out:
            print("Shell STDOUT output: \n'%s'\n" % out)
        if err:
            print("Shell STDERR output: \n'%s'\n" % err)

    return(out)


def untar(fname):
    '''Untar a tarred and compressed file'''

    if (fname.endswith("tar.gz")):
        tar = tarfile.open(fname, "r:gz")
        tar.extractall()
        tar.close()
    elif (fname.endswith("tar")):
        tar = tarfile.open(fname, "r:")
        tar.extractall()
        tar.close()


def pause_tool_execution(str):
    '''Pause the script for manual debugging of the VM before continuing'''

    print('Pause: "%s"' % str)
    raw_input('Press Enter to continue\n')


def banner(description):
    '''Display a bannerized print'''

    banner = len(description)
    if banner > 100:
        banner = 100

    # First banner
    print('\n')
    for c in range(banner):
        print('*', end='')

    # Add description
    print('\n%s' % description)

    # Final banner
    for c in range(banner):
        print('*', end='')
    print('\n')


def demo(args, title, description):
    '''Pause the script to provide demo information'''

    if not args.demo:
        return

    banner = len(description)
    if banner > 100:
        banner = 100

    # First banner
    print('\n')
    for c in range(banner):
        print('*', end='')

    # Add DEMO string
    print('\n%s'.ljust(banner - len('DEMO')) % 'DEMO')

    # Add title formatted to banner length
    print('%s'.ljust(banner - len(title)) % title)

    # Add description
    print('%s' % description)

    # Final banner
    for c in range(banner):
        print('*', end='')
    print('\n')

    if not args.force:
        raw_input('Press Enter to continue with demo...')
    else:
        print('Demo: Continuing with Demo')


def curl(*args):
    '''Use curl to retrieve a file from a URI'''

    curl_path = '/usr/bin/curl'
    curl_list = [curl_path]
    for arg in args:
        curl_list.append(arg)
    curl_result = subprocess.Popen(
        curl_list,
        stderr=subprocess.PIPE,
        stdout=subprocess.PIPE).communicate()[0]
    return curl_result


def linux_ver():
    '''Determine Linux version - Ubuntu or Centos

    Fail if it is not one of those.
    Return the long string for output
    '''

    find_os = platform.linux_distribution()
    if re.search('Centos', find_os[0], re.IGNORECASE):
        linux = 'centos'
    elif re.search('Ubuntu', find_os[0], re.IGNORECASE):
        linux = 'ubuntu'
    else:
        print('Linux "%s" is not supported yet' % find_os[0])
        sys.exit(1)

    return(linux)


def linux_ver_det():
    '''Determine Linux version - Ubuntu or Centos

    Return the long string for output
    '''

    return(str(platform.linux_distribution()))


def docker_ver(args):
    '''Display docker version'''

    oldstr = run_shell(args, "docker --version | awk '{print $3}'")
    newstr = oldstr.replace(",", "")
    return(newstr.rstrip())


def tools_versions(args, str):
    '''A Dictionary of tools and their versions

    Defaults are populated by tested well known versions.

    User can then overide each individual tool.

    Return a Version for a string.
    '''

    tools = [
        "kolla",
        "helm",
        "kubernetes",
        "ansible",
        "jinja2"]

    # This should match up with the defaults set in parse_args
    #            kolla    helm     k8s      ansible    jinja2
    versions = ["ocata", "2.7.2", "1.9.1", "2.4.2.0", "2.10"]

    tools_dict = {}
    # Generate dictionary
    for i in range(len(tools)):
        tools_dict[tools[i]] = versions[i]

    # Now overide based on user input - first
    if tools_dict["kolla"] is not args.image_version:
        tools_dict["kolla"] = args.image_version
    if tools_dict["helm"] is not args.helm_version:
        tools_dict["helm"] = args.helm_version
    if tools_dict["kubernetes"] is not args.k8s_version:
        tools_dict["kubernetes"] = args.k8s_version
    if tools_dict["ansible"] is not args.ansible_version:
        tools_dict["ansible"] = args.ansible_version
    if tools_dict["jinja2"] is not args.jinja2_version:
        tools_dict["jinja2"] = args.jinja2_version

    return(tools_dict[str])


def print_versions(args):
    '''Print out lots of information

    Tool versions, networking, user options and more
    '''

    banner('Kubernetes - Bring up a Kubernetes Cluster')
    if args.edit_globals:
        print('  *globals.yaml will be editable with this option*\n')

    if args.edit_cloud:
        print('  *cloud.yaml will be editable with this option*\n')

    # This a good place to install docker - as it's always needed and we
    # need the version anyway

    # Note later versions of ubuntu require a change:
    # https://github.com/moby/moby/issues/15651
    # sudo vi /lib/systemd/system/docker.service
    # ExecStart=/usr/bin/dockerd -H fd:// $DOCKER_OPTS -s overlay2
    # sudo systemctl daemon-reload
    # sudo systemctl restart docker
    # sudo docker info
    if linux_ver() == 'centos':
        run_shell(args, 'sudo yum install -y docker')
    else:
        run_shell(args, 'sudo apt autoremove -y && sudo apt autoclean')
        run_shell(args, 'sudo apt-get install -y docker.io')

    print('\nLinux Host Info:    %s' % linux_ver_det())

    print('\nNetworking Info:')
    print('  Management Int:     %s' % args.MGMT_INT)
    print('  Neutron Int:        %s' % args.NEUTRON_INT)
    print('  Management IP:      %s' % args.mgmt_ip)
    print('  VIP Keepalive:      %s' % args.vip_ip)
    print('  CNI/SDN:            %s' % args.cni)

    print('\nTool Versions:')
    print('  Docker version:     %s' % docker_ver(args))
    print('  Helm version:       %s' % tools_versions(args, 'helm'))
    print('  K8s version:        %s'
          % tools_versions(args, 'kubernetes').rstrip())
    print('  Ansible version:    %s' %
          tools_versions(args, 'ansible').rstrip())
    print('  Jinja2 version:     %s' %
          tools_versions(args, 'jinja2').rstrip())

    print('\nOpenStack Versions:')
    print('  Base image version: %s' % args.base_distro)
    print('  Docker repo:        %s' % args.docker_repo)
    print('  Openstack version:  %s' % tools_versions(args, 'kolla'))
    print('  Image Tag version:  %s' % kolla_get_image_tag(args))

    print('\nOptions:')
    print('  Logging enabled:    %s' % args.logs)
    print('  Dev mode enabled:   %s' % args.dev_mode)
    print('  No Network:         %s' % args.no_network)
    print('  Demo mode:          %s' % args.demo)
    print('  Edit Cloud:         %s' % args.edit_cloud)
    print('  Edit Globals:       %s' % args.edit_globals)
    print('\n')
    time.sleep(2)


def populate_ip_addresses(args):
    '''Populate the management and vip ip addresses

    By either finding the user input or finding them from
    the users system
    '''

    if linux_ver() == 'centos':
        run_shell(args, 'sudo yum install -y nmap')
    else:
        run_shell(args, 'sudo apt-get install -y nmap')

    # Populate Management IP Address
    if args.mgmt_ip is 'None':
        mgt = run_shell(
            args,
            "ip add show %s | awk ' / inet / {print $2}'  | cut -f1 -d'/'"
            % args.MGMT_INT)
        args.mgmt_ip = mgt.strip()
        if args.mgmt_ip is None:
            print('    *Kubernetes - No IP Address found on %s*')
            sys.exit(1)

    # Populate VIP IP Address - by finding an unused IP on MGMT subnet
    if args.vip_ip is 'None':
        start_ip = args.mgmt_ip[:args.mgmt_ip.rfind(".")]

        r = list(range(2, 253))
        random.shuffle(r)
        for k in r:
            vip = run_shell(args, 'sudo nmap -sP -PR %s.%s' % (start_ip, k))
            if "Host seems down" in vip:
                args.vip_ip = start_ip + '.' + str(k)
                break


def k8s_create_repo(args):
    '''Create a k8s repository file'''

    if linux_ver() == 'centos':
        name = './kubernetes.repo'
        repo = '/etc/yum.repos.d/kubernetes.repo'
        with open(name, "w") as w:
            w.write("""\
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
""")
        # todo: add -H to all sudo's see if it works in both envs
        run_shell(args, 'sudo mv ./kubernetes.repo %s' % repo)
    else:
        run_shell(args,
                  'curl -s https://packages.cloud.google.com'
                  '/apt/doc/apt-key.gpg '
                  '| sudo -E apt-key add -')
        name = './kubernetes.list'
        repo = '/etc/apt/sources.list.d/kubernetes.list'
        with open(name, "w") as w:
            w.write("""\
deb http://apt.kubernetes.io/ kubernetes-xenial main
""")
        run_shell(args, 'sudo mv ./kubernetes.list %s' % repo)
        run_shell(args, 'sudo apt-get update')


def k8s_wait_for_kube_system(args):
    '''Wait for basic k8s to come up'''

    TIMEOUT = 2000  # Give k8s 2000s to come up
    RETRY_INTERVAL = 10
    elapsed_time = 0
    prev_cnt = 0
    base_pods = 6

    print('(%02d/%d) Kubernetes - Wait for basic '
          'Kubernetes (6 pods) infrastructure'
          % (PROGRESS, K8S_FINAL_PROGRESS))

    while True:
        pod_status = run_shell(args,
                               'kubectl get pods -n kube-system --no-headers')
        nlines = len(pod_status.splitlines())
        if nlines == 6:
            print(
                '  *All pods %s/%s are started, continuing*' %
                (nlines, base_pods))
            run_shell(args, 'kubectl get pods -n kube-system')
            break
        elif elapsed_time < TIMEOUT:
            if nlines < 0:
                cnt = 0
            else:
                cnt = nlines

            if elapsed_time is not 0:
                if cnt is not prev_cnt:
                    print(
                        "  *Running pod(s) status after %d seconds %s:%s*"
                        % (elapsed_time, cnt, base_pods))
            prev_cnt = cnt
            time.sleep(RETRY_INTERVAL)
            elapsed_time = elapsed_time + RETRY_INTERVAL
            continue
        else:
            # Dump verbose output in case it helps...
            print(pod_status)
            raise AbortScriptException(
                "Kubernetes - did not come up after {0} seconds!"
                .format(elapsed_time))
    add_one_to_progress()


def k8s_wait_for_pod_start(args, chart):
    '''Wait for a chart to start'''

    # Useful for debugging issues when Service fails to start
    return

    if 'cinder' in chart:
        chart = 'cinder'

    if 'nova' in chart:
        chart = 'nova'

    time.sleep(3)

    while True:
        chart_up = run_shell(args,
                             'kubectl get pods --no-headers --all-namespaces'
                             ' | grep -i "%s" | wc -l' % chart)
        if int(chart_up) == 0:
            print('  *Kubernetes - chart "%s" not started yet*' % chart)
            time.sleep(3)
            continue
        else:
            print('  *Kubernetes - chart "%s" is started*' % chart)
            break


def k8s_wait_for_running_negate(args, timeout=None):
    '''Query get pods until only state is Running'''

    if timeout is None:
        TIMEOUT = 1000
    else:
        TIMEOUT = timeout

    RETRY_INTERVAL = 3

    print('  Wait for all pods to be in Running state:')

    elapsed_time = 0
    prev_not_running = 0
    while True:
        etcd_check = run_shell(args,
                               'kubectl get pods --no-headers --all-namespaces'
                               ' | grep -i "request timed out" | wc -l')

        if int(etcd_check) != 0:
            print('Kubernetes - etcdserver is busy - '
                  'retrying after brief pause')
            time.sleep(15)
            continue

        not_running = run_shell(
            args,
            'kubectl get pods --no-headers --all-namespaces | '
            'grep -v "Running" | wc -l')

        if int(not_running) != 0:
            if prev_not_running != not_running:
                print("    *%02d pod(s) are not in Running state*"
                      % int(not_running))
                time.sleep(RETRY_INTERVAL)
                elapsed_time = elapsed_time + RETRY_INTERVAL
                prev_not_running = not_running
            continue
        else:
            print('    *All pods are in Running state*')
            time.sleep(1)
            break

        if elapsed_time > TIMEOUT:
            # Dump verbose output in case it helps...
            print(int(not_running))
            raise AbortScriptException(
                "Kubernetes did not come up after {0} 1econds!"
                .format(elapsed_time))
        sys.exit(1)


def k8s_wait_for_vm(args, vm):
    """Wait for a vm to be listed as running in nova list"""

    TIMEOUT = 50
    RETRY_INTERVAL = 5

    print("  Kubernetes - Wait for VM %s to be in running state:" % vm)
    elapsed_time = 0

    while True:
        nova_out = run_shell(args,
                             '.  ~/keystonerc_admin; nova list | grep %s' % vm)
        if not re.search('Running', nova_out):
            print('    *Kubernetes - VM %s is not Running yet - '
                  'wait 15s*' % vm)
            time.sleep(RETRY_INTERVAL)
            elapsed_time = elapsed_time + RETRY_INTERVAL
            if elapsed_time > TIMEOUT:
                print('VM %s did not come up after %s seconds! '
                      'This is probably not in a healthy state' %
                      (vm, int(elapsed_time)))
                break
            continue
        else:
            print('    *Kubernetes - VM %s is Running*' % vm)
            break


def add_one_to_progress():
    '''Add one to progress meter'''

    global PROGRESS
    PROGRESS += 1


def clean_progress():
    '''Reset progress meter to zero'''

    global PROGRESS
    PROGRESS = 0


def print_progress(process, msg, finalctr, add_one=False):
    '''Print a message with a progress account'''

    if add_one:
        add_one_to_progress()
    print("(%02d/%02d) %s - %s" % (PROGRESS, finalctr, process, msg))
    add_one_to_progress()


def k8s_install_tools(args):
    '''Basic tools needed for first pass'''

    # Reset kubeadm if it's a new installation
    if not args.openstack:
        run_shell(args, 'sudo kubeadm reset')

    print_progress('Kubernetes',
                   'Installing environment',
                   K8S_FINAL_PROGRESS)

    if linux_ver() == 'centos':
        run_shell(args, 'sudo yum update -y; sudo yum upgrade -y')
        run_shell(args, 'sudo yum install -y qemu epel-release bridge-utils')
        run_shell(args,
                  'sudo yum install -y python-pip python-devel libffi-devel '
                  'gcc openssl-devel sshpass')
        run_shell(args, 'sudo yum install -y git crudini jq ansible curl lvm2')
    else:
        run_shell(args, 'sudo apt-get update; sudo apt-get dist-upgrade -y '
                  '--allow-downgrades --no-install-recommends')
        run_shell(args, 'sudo apt-get install -y qemu bridge-utils')
        run_shell(args, 'sudo apt-get install -y python-dev libffi-dev gcc '
                  'libssl-dev python-pip sshpass apt-transport-https')
        run_shell(args, 'sudo apt-get install -y git gcc crudini jq '
                  'ansible curl lvm2')

    curl(
        '-L',
        'https://bootstrap.pypa.io/get-pip.py',
        '-o', '/tmp/get-pip.py')
    run_shell(args, 'sudo python /tmp/get-pip.py')

    run_shell(args,
              'sudo -H pip install ansible==%s' %
              tools_versions(args, 'ansible'))

    # Standard jinja2 in Centos7(2.9.6) is broken
    run_shell(args,
              'sudo -H pip install Jinja2==%s' %
              tools_versions(args, 'jinja2'))

    # https://github.com/ansible/ansible/issues/26670
    run_shell(args, 'sudo -H pip uninstall pyOpenSSL -y')
    run_shell(args, 'sudo -H pip install pyOpenSSL')


def k8s_setup_ntp(args):
    '''Setup NTP'''

    print_progress('Kubernetes',
                   'Setup NTP',
                   K8S_FINAL_PROGRESS)

    if linux_ver() == 'centos':
        run_shell(args, 'sudo yum install -y ntp')
        run_shell(args, 'sudo systemctl enable ntpd.service')
        run_shell(args, 'sudo systemctl start ntpd.service')
    else:
        run_shell(args, 'sudo apt-get install -y ntp')
        run_shell(args, 'sudo systemctl restart ntp')


def k8s_turn_things_off(args):
    '''Currently turn off SELinux and Firewall'''

    if linux_ver() == 'centos':
        print_progress('Kubernetes',
                       'Turn off SELinux',
                       K8S_FINAL_PROGRESS)

        run_shell(args, 'sudo setenforce 0')
        run_shell(args,
                  'sudo sed -i s/enforcing/permissive/g /etc/selinux/config')

    print_progress('Kubernetes',
                   'Turn off firewall and ISCSID',
                   K8S_FINAL_PROGRESS)

    if linux_ver() == 'centos':
        run_shell(args, 'sudo systemctl stop firewalld')
        run_shell(args, 'sudo systemctl disable firewalld')
    else:
        run_shell(args, 'sudo ufw disable')
        run_shell(args, 'sudo systemctl stop iscsid')
        run_shell(args, 'sudo systemctl stop iscsid.service')


def k8s_install_k8s(args):
    '''Necessary repo to install kubernetes and tools

    This is often broken and may need to be more programatic
    '''

    print_progress('Kubernetes',
                   'Create Kubernetes repo and install Kubernetes ',
                   K8S_FINAL_PROGRESS)

    run_shell(args, 'sudo -H pip install --upgrade pip')
    k8s_create_repo(args)

    demo(args, 'Installing Kubernetes', 'Installing docker ebtables '
         'kubelet-%s kubeadm-%s kubectl-%s kubernetes-cni' %
         (tools_versions(args, 'kubernetes'),
          tools_versions(args, 'kubernetes'),
          tools_versions(args, 'kubernetes')))

    if linux_ver() == 'centos':
        run_shell(args,
                  'sudo yum install -y ebtables kubelet-%s '
                  'kubeadm-%s kubectl-%s kubernetes-cni'
                  % (tools_versions(args, 'kubernetes'),
                     tools_versions(args, 'kubernetes'),
                     tools_versions(args, 'kubernetes')))
    else:
        # todo - this breaks when ubuntu steps up a revision to -01 etc
        run_shell(args,
                  'sudo apt-get install -y --allow-downgrades '
                  'ebtables kubelet=%s-00 kubeadm=%s-00 kubectl=%s-00 '
                  'kubernetes-cni' % (tools_versions(args, 'kubernetes'),
                                      tools_versions(args, 'kubernetes'),
                                      tools_versions(args, 'kubernetes')))


def k8s_setup_dns(args):
    '''DNS services and kubectl fixups'''

    print_progress('Kubernetes',
                   'Start docker and setup the DNS server with '
                   'the service CIDR',
                   K8S_FINAL_PROGRESS)

    run_shell(args, 'sudo systemctl enable docker')
    run_shell(args, 'sudo systemctl start docker')
    run_shell(
        args,
        'sudo cp /etc/systemd/system/kubelet.service.d/10-kubeadm.conf /tmp')
    run_shell(args, 'sudo chmod 777 /tmp/10-kubeadm.conf')
    run_shell(args,
              'sudo sed -i s/10.96.0.10/10.3.3.10/g /tmp/10-kubeadm.conf')

    # https://github.com/kubernetes/kubernetes/issues/53333#issuecomment-339793601
    # https://stackoverflow.com/questions/46726216/kubelet-fails-to-get-cgroup-stats-for-docker-and-kubelet-services
    run_shell(
        args,
        'sudo echo Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=systemd" '
        '>> /tmp/10-kubeadm.conf')
    run_shell(
        args,
        'sudo echo Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false" '
        '>> /tmp/10-kubeadm.conf')
    run_shell(
        args,
        'sudo echo Environment="KUBELET_DOS_ARGS=--runtime-cgroups=/systemd'
        '/system.slice --kubelet-cgroups=/systemd/system.slice --hostname-'
        'override=$(hostname) --fail-swap-on=false" >> /tmp/10-kubeadm.conf')

    run_shell(args, 'sudo mv /tmp/10-kubeadm.conf '
              '/etc/systemd/system/kubelet.service.d/10-kubeadm.conf')


def k8s_reload_service_files(args):
    '''Service files where modified so bring them up again'''

    print_progress('Kubernetes',
                   'Reload the hand-modified service files',
                   K8S_FINAL_PROGRESS)

    run_shell(args, 'sudo systemctl daemon-reload')


def k8s_start_kubelet(args):
    '''Start kubelet'''

    print_progress('Kubernetes',
                   'Enable and start kubelet',
                   K8S_FINAL_PROGRESS)

    demo(args, 'Enable and start kubelet',
         'kubelet is a command line interface for running commands '
         'against Kubernetes clusters')

    run_shell(args, 'sudo systemctl enable kubelet')
    run_shell(args, 'sudo systemctl start kubelet')


def k8s_fix_iptables(args):
    '''Maybe Centos only but this needs to be changed to proceed'''

    reload_sysctl = False
    print_progress('Kubernetes',
                   'Fix iptables to enable bridging',
                   K8S_FINAL_PROGRESS)

    demo(args, 'Centos fix bridging',
         'Setting net.bridge.bridge-nf-call-iptables=1 '
         'in /etc/sysctl.conf')

    run_shell(args, 'sudo cp /etc/sysctl.conf /tmp')
    run_shell(args, 'sudo chmod 777 /tmp/sysctl.conf')

    with open('/tmp/sysctl.conf', 'r+') as myfile:
        contents = myfile.read()
        if not re.search('net.bridge.bridge-nf-call-ip6tables=1', contents):
            myfile.write('net.bridge.bridge-nf-call-ip6tables=1' + '\n')
            reload_sysctl = True
        if not re.search('net.bridge.bridge-nf-call-iptables=1', contents):
            myfile.write('net.bridge.bridge-nf-call-iptables=1' + '\n')
            reload_sysctl = True
    if reload_sysctl is True:
        run_shell(args, 'sudo mv /tmp/sysctl.conf /etc/sysctl.conf')
        run_shell(args, 'sudo sysctl -p')


def k8s_deploy_k8s(args):
    '''Start the kubernetes master'''

    print_progress('Kubernetes',
                   'Deploying Kubernetes with kubeadm (Slow!)',
                   K8S_FINAL_PROGRESS)

    demo(args, 'Initializes your Kubernetes Master',
         'One of the most frequent criticisms of Kubernetes is that it is '
         'hard to install.\n'
         'Kubeadm is a new tool that is part of the Kubernetes distribution '
         'that makes this easier')
    demo(args, 'The Kubernetes Control Plane',
         'The Kubernetes control plane consists of the Kubernetes '
         'API server\n'
         '(kube-apiserver), controller manager (kube-controller-manager),\n'
         'and scheduler (kube-scheduler). The API server depends '
         'on etcd so\nan etcd cluster is also required.\n'
         'https://www.ianlewis.org/en/how-kubeadm-initializes-'
         'your-kubernetes-master')
    demo(args, 'kubeadm and the kubelet',
         'Kubernetes has a component called the Kubelet which '
         'manages containers\nrunning on a single host. It allows us to '
         'use Kubelet to manage the\ncontrol plane components. This is '
         'exactly what kubeadm sets us up to do.\n'
         'We run:\n'
         'kubeadm init --pod-network-cidr=10.1.0.0/16 '
         '--service-cidr=10.3.3.0/24 --ignore-preflight-errors=all '
         'and check output\n'
         'Run: "watch -d sudo docker ps" in another window')
    demo(args, 'Monitoring Kubernetes',
         'What monitors Kubelet and make sure it is always running? This '
         'is where we use systemd.\n Systemd is started as PID 1 so the OS\n'
         'will make sure it is always running, systemd makes sure the '
         'Kubelet is running, and the\nKubelet makes sure our containers '
         'with the control plane components are running.')

    if args.demo:
        print(run_shell(args,
                        'sudo kubeadm init --pod-network-cidr=10.1.0.0/16 '
                        '--service-cidr=10.3.3.0/24 '
                        '--ignore-preflight-errors=all'))
        demo(args, 'What happened?',
             'We can see above that kubeadm created the necessary '
             'certificates for\n'
             'the API, started the control plane components, '
             'and installed the essential addons.\n'
             'The join command is important - it allows other nodes '
             'to be added to the existing resources\n'
             'Kubeadm does not mention anything about the Kubelet but '
             'we can verify that it is running:')
        print(run_shell(args,
                        'sudo ps aux | grep /usr/bin/kubelet | grep -v grep'))
        demo(args,
             'Kubelet was started. But what is it doing? ',
             'The Kubelet will monitor the control plane components '
             'but what monitors Kubelet and make sure\n'
             'it is always running? This is where we use systemd. '
             'Systemd is started as PID 1 so the OS\n'
             'will make sure it is always running, systemd makes '
             'sure the Kubelet is running, and the\nKubelet '
             'makes sure our containers with the control plane '
             'components are running.')
    else:
        out = run_shell(args,
                        'sudo kubeadm init --pod-network-cidr=10.1.0.0/16 '
                        '--service-cidr=10.3.3.0/24 '
                        '--ignore-preflight-errors=all')
        # Even in no-verbose mode, we need to display the join command to
        # enabled multi-node
        for line in out.splitlines():
            if re.search('kubeadm join', line):
                print('  You can now join any number of machines by '
                      'running the following on each node as root:')
                line += ' ' * 2
                print(line)


def k8s_load_kubeadm_creds(args):
    '''This ensures the user gets output from 'kubectl get pods'''

    print_progress('Kubernetes',
                   'Load kubeadm credentials into the system',
                   K8S_FINAL_PROGRESS)

    home = os.environ['HOME']
    kube = os.path.join(home, '.kube')
    config = os.path.join(kube, 'config')

    if not os.path.exists(kube):
        os.makedirs(kube)
    run_shell(args, 'sudo -H cp /etc/kubernetes/admin.conf %s' % config)
    run_shell(args, 'sudo chmod 777 %s' % kube)
    run_shell(args, 'sudo -H chown $(id -u):$(id -g) $HOME/.kube/config')
    demo(args, 'Verify Kubelet',
         'Kubelete should be running our control plane components and be\n'
         'connected to the API server (like any other Kubelet node.\n'
         'Run "watch -d kubectl get pods --all-namespaces" in another '
         'window\nNote that the kube-dns-* pod is not ready yet. We do '
         'not have a network yet')
    demo(args, 'Verifying the Control Plane Components',
         'We can see that kubeadm created a /etc/kubernetes/ '
         'directory so check\nout what is there.')
    if args.demo:
        print(run_shell(args, 'ls -lh /etc/kubernetes/'))
        demo(args, 'Files created by kubectl',
             'The admin.conf and kubelet.conf are yaml files that mostly\n'
             'contain certs used for authentication with the API. The pki\n'
             'directory contains the certificate authority certs, '
             'API server\ncerts, and tokens:')
        print(run_shell(args, 'ls -lh /etc/kubernetes/pki'))
        demo(args, 'The manifests directory ',
             'This directory is where things get interesting. In the\n'
             'manifests directory we have a number of json files for our\n'
             'control plane components.')
        print(run_shell(args, 'sudo ls -lh /etc/kubernetes/manifests/'))
        demo(args, 'Pod Manifests',
             'If you noticed earlier the Kubelet was passed the\n'
             '--pod-manifest-path=/etc/kubernetes/manifests flag '
             'which tells\nit to monitor the files in the '
             '/etc/kubernetes/manifests directory\n'
             'and makes sure the components defined therein are '
             'always running.\nWe can see that they are running my '
             'checking with the local Docker\nto list the running containers.')
        print(
            run_shell(args,
                      'sudo docker ps --format="table {{.ID}}\t{{.Image}}"'))
        demo(args, 'Note above containers',
             'We can see that etcd, kube-apiserver, '
             'kube-controller-manager, and\nkube-scheduler are running.')
        demo(args, 'How can we connect to containers?',
             'If we look at each of the json files in the '
             '/etc/kubernetes/manifests\ndirectory we can see that they '
             'each use the hostNetwork: true option\nwhich allows the '
             'applications to bind to ports on the host just as\n'
             'if they were running outside of a container.')
        demo(args, 'Connect to the API',
             'So we can connect to the API servers insecure local port.\n'
             'curl http://127.0.0.1:8080/version')
        print(run_shell(args, 'sudo curl http://127.0.0.1:8080/version'))
        demo(args, 'Secure port?', 'The API server also binds a secure'
             'port 443 which\nrequires a client cert and authentication. '
             'Be careful to use the\npublic IP for your master here.\n'
             'curl --cacert /etc/kubernetes/pki/ca.pem '
             'https://10.240.0.2/version')
        print(run_shell(args, 'curl --cacert /etc/kubernetes/pki/ca.pem '
                        'https://10.240.0.2/version'))
    print('  Note "kubectl get pods --all-namespaces" should work now')


def k8s_deploy_cni(args):
    '''Deploy CNI/SDN to K8s cluster'''

    if args.cni == 'weave':
        print_progress('Kubernetes',
                       'Deploy pod network SDN using Weave CNI',
                       K8S_FINAL_PROGRESS)

        weave_ver = run_shell(args,
                              "echo $(kubectl version | base64 | tr -d '\n')")
        curl(
            '-L',
            'https://cloud.weave.works/k8s/net?k8s-version=%s' % weave_ver,
            '-o', '/tmp/weave.yaml')

        # Don't allow Weave Net to crunch ip's used by k8s
        name = '/tmp/ipalloc.txt'
        with open(name, "w") as w:
            w.write("""\
                - name: IPALLOC_RANGE
                  value: 10.0.0.0/16
""")
        run_shell(args, 'chmod 777 /tmp/ipalloc.txt /tmp/weave.yaml')
        run_shell(args, "sed -i '/fieldPath: spec.nodeName/ r "
                  "/tmp/ipalloc.txt' /tmp/weave.yaml")

        run_shell(
            args,
            'kubectl apply -f /tmp/weave.yaml')
        return

    # If not weave then canal...
    # The ip range in canal.yaml,
    # /etc/kubernetes/manifests/kube-controller-manager.yaml
    # and the kubeadm init command must match
    print_progress('Kubernetes',
                   'Deploy pod network SDN using Canal CNI',
                   K8S_FINAL_PROGRESS)

    answer = curl(
        '-L',
        'https://raw.githubusercontent.com/projectcalico/canal/master/'
        'k8s-install/1.7/rbac.yaml',
        '-o', '/tmp/rbac.yaml')
    logger.debug(answer)
    run_shell(args, 'kubectl create -f /tmp/rbac.yaml')

    if args.demo:
        demo(args, 'Why use a CNI Driver?',
             'Container Network Interface (CNI) is a '
             'specification started by CoreOS\n'
             'with the input from the wider open '
             'source community aimed to make network\n'
             'plugins interoperable between container '
             'execution engines. It aims to be\n'
             'as common and vendor-neutral as possible '
             'to support a wide variety of\n'
             'networking options from MACVLAN to modern '
             'SDNs such as Weave and flannel.\n\n'
             'CNI is growing in popularity. It got its '
             'start as a network plugin\n'
             'layer for rkt, a container runtime from CoreOS. '
             'CNI is getting even\n'
             'wider adoption with Kubernetes adding support for '
             'it. Kubernetes\n'
             'accelerates development cycles while simplifying '
             'operations, and with\n'
             'support for CNI is taking the next step toward a '
             'common ground for\nnetworking.')
    answer = curl(
        '-L',
        'https://raw.githubusercontent.com/projectcalico/canal/master/'
        'k8s-install/1.7/canal.yaml',
        '-o', '/tmp/canal.yaml')
    logger.debug(answer)
    run_shell(args, 'sudo chmod 777 /tmp/canal.yaml')
    run_shell(args,
              'sudo sed -i s@10.244.0.0/16@10.1.0.0/16@ /tmp/canal.yaml')
    run_shell(args, 'kubectl create -f /tmp/canal.yaml')
    demo(args,
         'Wait for CNI to be deployed',
         'A successfully deployed CNI will result in a valid dns pod')


def k8s_add_api_server(args):
    '''Add API Server'''

    print_progress('Kubernetes',
                   'Add API Server',
                   K8S_FINAL_PROGRESS)

    run_shell(args, 'sudo mkdir -p /etc/nodepool/')
    run_shell(args, 'sudo echo %s > /tmp/primary_node_private' % args.mgmt_ip)
    run_shell(args, 'sudo mv -f /tmp/primary_node_private /etc/nodepool')


def k8s_schedule_master_node(args):
    '''Make node an AIO

    Normally master node won't be happy - unless you do this step to
    make it an AOI deployment

    While the command says "taint" the "-" at the end is an "untaint"
    '''

    print_progress('Kubernetes',
                   'Mark master node as schedulable by untainting the node',
                   K8S_FINAL_PROGRESS)

    demo(args,
         'Running on the master is different though',
         'There is a special annotation on our node '
         'telling Kubernetes not to\n'
         'schedule containers on our master node.')
    run_shell(args,
              'kubectl taint nodes '
              '--all=true node-role.kubernetes.io/master:NoSchedule-')


def kolla_update_rbac(args):
    '''Override the default RBAC settings'''

    print_progress('Kolla',
                   'Overide default RBAC settings',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Role-based access control (RBAC)',
         'A method of regulating access to computer or '
         'network resources based\n'
         'on the roles of individual users within an enterprise. '
         'In this context,\n'
         'access is the ability of an individual user to perform a '
         'specific task\n'
         'such as view, create, or modify a file.')
    name = '/tmp/rbac'
    with open(name, "w") as w:
        w.write("""\
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: system:masters
- kind: Group
  name: system:authenticated
- kind: Group
  name: system:unauthenticated
""")
    if args.demo:
        print(run_shell(args, 'kubectl apply -f /tmp/rbac'))
        demo(args, 'Note the cluster-admin has been replaced', '')
    else:
        run_shell(args, 'kubectl apply -f /tmp/rbac')


def kolla_install_deploy_helm(args):
    '''Deploy helm binary'''

    print_progress('Kolla',
                   'Deploy Helm Tiller pod',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Download the version of helm requested and install it',
         'Installing means the Tiller Server will be instantiated in a pod')
    curl('-sSL',
         'https://storage.googleapis.com/kubernetes-helm/'
         'helm-v%s-linux-amd64.tar.gz' % args.helm_version,
         '-o',
         '/tmp/helm-v%s-linux-amd64.tar.gz' % args.helm_version)
    untar('/tmp/helm-v%s-linux-amd64.tar.gz' % args.helm_version)
    run_shell(args, 'sudo mv -f linux-amd64/helm /usr/local/bin/helm')
    run_shell(args, 'helm init')
    k8s_wait_for_pod_start(args, 'tiller')
    k8s_wait_for_running_negate(args)
    # Check for helm version
    # Todo - replace this to using json path to check for that field
    while True:
        out = run_shell(args,
                        'helm version | grep "%s" | wc -l' %
                        args.helm_version)
        if int(out) == 2:
            print_progress('Kolla',
                           'Helm successfully installed',
                           KOLLA_FINAL_PROGRESS)
            break
        else:
            time.sleep(1)
            continue

    demo(args, 'Check running pods..',
         'Note that the helm version in server and client is the same.\n'
         'Tiller is ready to respond to helm chart requests')


def is_running(args, process):
    '''Check if a process is running'''

    s = run_shell(args, 'ps awx')
    for x in s:
        if re.search(process, x):
            return True
        else:
            return False


def k8s_cleanup(args):
    '''Cleanup on Isle 9'''

    if args.cleanup is True or args.complete_cleanup is True:
        clean_progress()
        banner('Kubernetes - Cleaning up an existing Kubernetes Cluster')

        print_progress('Kubernetes',
                       'Kubeadm reset',
                       K8S_CLEANUP_PROGRESS,
                       True)

        run_shell(args, 'sudo kubeadm reset')

        print_progress('Kubernetes',
                       'Delete /etc files and dirs',
                       K8S_CLEANUP_PROGRESS)

        run_shell(args, 'sudo rm -rf /etc/kolla*')
        run_shell(args, 'sudo rm -rf /etc/kubernetes')
        run_shell(args, 'sudo rm -rf /etc/kolla-kubernetes')

        print_progress('Kubernetes',
                       'Delete /var files and dirs',
                       K8S_CLEANUP_PROGRESS)

        run_shell(args, 'sudo rm -rf /var/lib/kolla*')
        run_shell(args, 'sudo rm -rf /var/etcd')
        run_shell(args, 'sudo rm -rf /var/run/kubernetes/*')
        run_shell(args, 'sudo rm -rf /var/lib/kubelet/*')
        run_shell(args, 'sudo rm -rf /var/run/lock/kubelet.lock')
        run_shell(args, 'sudo rm -rf /var/run/lock/api-server.lock')
        run_shell(args, 'sudo rm -rf /var/run/lock/etcd.lock')
        run_shell(args, 'sudo rm -rf /var/run/lock/kubelet.lock')

        print_progress('Kubernetes',
                       'Delete /tmp',
                       K8S_CLEANUP_PROGRESS)

        run_shell(args, 'sudo rm -rf /tmp/*')

        if os.path.exists('/data'):
            print_progress('Kubernetes',
                           'Remove cinder volumes and data',
                           K8S_CLEANUP_PROGRESS)

            run_shell(args, 'sudo vgremove cinder-volumes -f')
            run_shell(args, 'sudo losetup -d /dev/loop0')
            run_shell(args, 'sudo rm -rf /data')

        print_progress('Kubernetes',
                       'Cleanup docker containers and images',
                       K8S_CLEANUP_PROGRESS)

        # Clean up docker containers
        run_shell(args,
                  "sudo docker rm $(sudo docker ps -q -f 'status=exited')")
        run_shell(args,
                  "sudo docker rmi $(sudo docker images -q -f "
                  "'dangling=true')")
        run_shell(args,
                  "sudo docker volume rm -f $(sudo docker volume "
                  "ls -qf dangling=true)")

        # Remove docker images on system
        run_shell(args,
                  "sudo docker rmi -f $(sudo docker images -a -q)")

        if args.complete_cleanup:
            print_progress('Kubernetes',
                           'Cleanup done. Highly recommend rebooting '
                           'your host',
                           K8S_CLEANUP_PROGRESS)
        else:
            print_progress('Kubernetes',
                           'Cleanup done. Will attempt '
                           'to proceed with installation. YMMV.\n',
                           K8S_CLEANUP_PROGRESS)

            clean_progress()
            add_one_to_progress()

    # After reboot, kubelet service comes back...
    run_shell(args, 'sudo kubeadm reset')


def kolla_install_repos(args):
    '''Installing the kolla repos

    For sanity I just delete a repo if already exists
    '''

    if args.no_git:
        print('(%02d/%d) Kolla - Not cloning kolla repos to preserve existing '
              'content' %
              (PROGRESS, KOLLA_FINAL_PROGRESS))
        add_one_to_progress()

    if not args.no_git:
        print('(%02d/%d) Kolla - Clone kolla-ansible' %
              (PROGRESS, KOLLA_FINAL_PROGRESS))
        add_one_to_progress()

        demo(args, 'Git cloning repos, then using pip to install them',
             'http://github.com/openstack/kolla-ansible\n'
             'http://github.com/openstack/kolla-kubernetes')

        if os.path.exists('./kolla-ansible'):
            run_shell(args, 'sudo rm -rf ./kolla-ansible')
        run_shell(args,
                  'git clone http://github.com/openstack/kolla-ansible')

        if os.path.exists('./kolla-kubernetes'):
            run_shell(args, 'sudo rm -rf ./kolla-kubernetes')
        print_progress('Kolla',
                       'Clone kolla-kubernetes',
                       KOLLA_FINAL_PROGRESS)

        run_shell(args,
                  'git clone http://github.com/openstack/kolla-kubernetes')

        if args.dev_mode:
            pause_tool_execution('DEV: edit kolla-kubernetes repo now')

    print_progress('Kolla',
                   'Install kolla-ansible and kolla-kubernetes',
                   KOLLA_FINAL_PROGRESS)

    run_shell(args,
              'sudo -H pip install -U kolla-ansible/ kolla-kubernetes/')

    if linux_ver() == 'centos':
        print_progress('Kolla',
                       'Copy default kolla-ansible configuration to /etc',
                       KOLLA_FINAL_PROGRESS)

        run_shell(args,
                  'sudo cp -aR /usr/share/kolla-ansible/etc_'
                  'examples/kolla /etc')
    else:
        print_progress('Kolla',
                       'Copy default kolla-ansible configuration to /etc',
                       KOLLA_FINAL_PROGRESS)

        run_shell(args,
                  'sudo cp -aR /usr/local/share/kolla-ansible/'
                  'etc_examples/kolla /etc')

    print_progress('Kolla',
                   'Copy default kolla-kubernetes configuration to /etc',
                   KOLLA_FINAL_PROGRESS)

    run_shell(args, 'sudo cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc')


def kolla_setup_loopback_lvm(args):
    '''Setup a loopback LVM for Cinder

    /opt/kolla-kubernetes/tests/bin/setup_gate_loopback_lvm.sh
    '''

    print_progress('Kolla',
                   'Setup Loopback LVM for Cinder (Slow!)',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Loopback LVM for Cinder',
         'Create a flat file on the filesystem and then loopback mount\n'
         'it so that it looks like a block-device attached to /dev/zero\n'
         'Then LVM manages it. This is useful for test and development\n'
         'It is also very slow and etcdserver may time out frequently')
    new = '/tmp/setup_lvm'
    with open(new, "w") as w:
        w.write("""
sudo mkdir -p /data/kolla
sudo df -h
sudo dd if=/dev/zero of=/data/kolla/cinder-volumes.img bs=5M count=2048
LOOP=$(losetup -f)
sudo losetup $LOOP /data/kolla/cinder-volumes.img
sudo parted -s $LOOP mklabel gpt
sudo parted -s $LOOP mkpart 1 0% 100%
sudo parted -s $LOOP set 1 lvm on
sudo partprobe $LOOP
sudo pvcreate -y $LOOP
sudo vgcreate -y cinder-volumes $LOOP
""")
    run_shell(args, 'bash %s' % new)


def kolla_install_os_client(args):
    '''Install Openstack Client'''

    print_progress('Kolla',
                   'Install Python Openstack Client',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Install Python packages',
         'python-openstackclient, python-neutronclient and '
         'python-cinderclient\nprovide the command-line '
         'clients for openstack')
    run_shell(args, 'sudo -H pip install python-openstackclient')
    run_shell(args, 'sudo -H pip install python-neutronclient')
    run_shell(args, 'sudo -H pip install python-cinderclient')


def kolla_gen_passwords(args):
    '''Generate the Kolla Passwords'''

    print_progress('Kolla',
                   'Generate default passwords via SPRNG',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Generate passwords',
         'This will populate all empty fields in the '
         '/etc/kolla/passwords.yml\n'
         'file using randomly generated values to secure the deployment')
    run_shell(args, 'sudo kolla-kubernetes-genpwd')


def kolla_create_namespace(args):
    '''Create a kolla namespace'''

    print_progress('Kolla',
                   'Create a Kubernetes namespace "kolla"',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Isolate the Kubernetes namespace',
         'Create a namespace using "kubectl create namespace kolla"')
    if args.demo:
        print(run_shell(args, 'kubectl create namespace kolla'))
    else:
        run_shell(args, 'kubectl create namespace kolla')


def kolla_label_nodes(args, node_list):
    '''Label the nodes according to the list passed in'''

    print_progress('Kolla',
                   'Label Nodes controller and compute',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Label the node',
         'Currently controller and compute')
    for node in node_list:
        print("  Label the AIO node as '%s'" % node)
        run_shell(args, 'kubectl label node $(hostname) %s=true' % node)


def k8s_check_exit(k8s_only):
    '''If the user only wants kubernetes and not kolla - stop here'''

    if k8s_only is True:
        print('Kubernetes Cluster is running and healthy and you do '
              'not wish to install kolla')
        sys.exit(1)


def kolla_modify_globals(args):
    '''Necessary additions and changes to the global.yml.

    Which is based on the users inputs
    '''

    print_progress('Kolla',
                   'Modify global.yml to setup network_interface '
                   'and neutron_interface',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Kolla uses two files currently to configure',
         'Here we are modifying /etc/kolla/globals.yml\n'
         'We are setting the management interface to "%s" '
         'and IP to %s\n' % (args.MGMT_INT, args.mgmt_ip) +
         'The interface for neutron(externally bound) "%s"\n'
         % args.NEUTRON_INT +
         'globals.yml is used when we run ansible to generate '
         'configs in further step')
    run_shell(args,
              "sudo sed -i 's/eth0/%s/g' /etc/kolla/globals.yml"
              % args.MGMT_INT)
    run_shell(args,
              "sudo sed -i 's/#network_interface/network_interface/g' "
              "/etc/kolla/globals.yml")
    run_shell(args,
              "sudo sed -i 's/10.10.10.254/%s/g' /etc/kolla/globals.yml" %
              args.mgmt_ip)
    run_shell(args,
              "sudo sed -i 's/eth1/%s/g' /etc/kolla/globals.yml"
              % args.NEUTRON_INT)
    run_shell(args,
              "sudo sed -i 's/#neutron_external_interface/"
              "neutron_external_interface/g' /etc/kolla/globals.yml")


def kolla_add_to_globals(args):
    '''Default section needed'''

    print_progress('Kolla',
                   'Add default config to globals.yml',
                   KOLLA_FINAL_PROGRESS)

    new = '/tmp/add'
    add_to = '/etc/kolla/globals.yml'

    with open(new, "w") as w:
        w.write("""
kolla_install_type: "source"
tempest_image_alt_id: "{{ tempest_image_id }}"
tempest_flavor_ref_alt_id: "{{ tempest_flavor_ref_id }}"

neutron_plugin_agent: "openvswitch"
api_interface_address: 0.0.0.0
tunnel_interface_address: 0.0.0.0
orchestration_engine: KUBERNETES
memcached_servers: "memcached"
keystone_admin_url: "http://keystone-admin:35357/v3"
keystone_internal_url: "http://keystone-internal:5000/v3"
keystone_public_url: "http://keystone-public:5000/v3"
glance_registry_host: "glance-registry"
neutron_host: "neutron"
keystone_database_address: "mariadb"
glance_database_address: "mariadb"
nova_database_address: "mariadb"
nova_api_database_address: "mariadb"
neutron_database_address: "mariadb"
cinder_database_address: "mariadb"
ironic_database_address: "mariadb"
placement_database_address: "mariadb"
rabbitmq_servers: "rabbitmq"
openstack_logging_debug: "True"
enable_haproxy: "no"
enable_heat: "no"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
enable_cinder_backend_iscsi: "yes"
enable_cinder_backend_rbd: "no"
enable_ceph: "no"
enable_elasticsearch: "no"
enable_kibana: "no"
glance_backend_ceph: "no"
cinder_backend_ceph: "no"
nova_backend_ceph: "no"
enable_neutron_provider_networks: "yes"
""")
    run_shell(args, 'cat %s | sudo tee -a %s' % (new, add_to))

    if args.edit_globals:
        pause_tool_execution('Pausing to edit the /etc/kolla/globals.yml file')

    demo(args, 'We have also added some basic config that is not defaulted',
         'Mainly Cinder and Database:')
    if args.demo:
        print(run_shell(args, 'sudo cat /tmp/add'))


def kolla_enable_qemu(args):
    '''Set libvirt type to QEMU'''

    print_progress('Kolla',
                   'Set libvirt type to QEMU',
                   KOLLA_FINAL_PROGRESS)
    run_shell(
        args,
        'sudo crudini --set /etc/kolla/nova-compute/nova.conf libvirt '
        'virt_type qemu')
    run_shell(
        args,
        'sudo crudini --set /etc/kolla/nova-compute/nova.conf libvirt '
        'cpu_mode none')
    UUID = run_shell(args,
                     "awk '{if($1 == \"cinder_rbd_secret_uuid: \")"
                     "{print $2}}' /etc/kolla/passwords.yml")
    run_shell(
        args,
        'sudo crudini --set /etc/kolla/nova-compute/nova.conf libvirt '
        'rbd_secret_uuid %s' % UUID)
    run_shell(
        args,
        'sudo crudini --set /etc/kolla/keystone/keystone.conf cache '
        'enabled False')

    # https://bugs.launchpad.net/kolla/+bug/1687459
    run_shell(args,
              'sudo service libvirt-bin stop')
    run_shell(args,
              'sudo update-rc.d libvirt-bin disable')
    run_shell(args,
              'sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd')


def kolla_gen_configs(args):
    '''Generate the configs using Jinja2

    Some version meddling here until things are more stable
    '''

    print_progress('Kolla',
                   'Generate the default configuration',
                   KOLLA_FINAL_PROGRESS)

    # globals.yml is used when we run ansible to generate configs
    demo(args, 'Explanation about generating configs',
         'There is absolutely no written description about the '
         'following steps: gen config and configmaps...\n'
         'The default configuration is generated by Ansible using '
         'the globals.yml and the generated password\n'
         'into files in /etc/kolla\n'
         '"kubectl create configmap" is called to wrap each '
         'microservice config into a configmap.\n'
         'When helm microchart is launched, it mounts the '
         'configmap into the container via a\n '
         'tmpfs bindmount and the configuration is read and '
         'processed by the microcharts\n'
         'container and the container then does its thing')

    demo(args, 'The command executed is',
         'cd kolla-kubernetes; sudo ansible-playbook -e '
         'ansible_python_interpreter=/usr/bin/python -e '
         '@/etc/kolla/globals.yml -e @/etc/kolla/passwords.yml '
         '-e CONFIG_DIR=/etc/kolla ./ansible/site.yml')

    demo(args, 'This is temporary',
         'The next gen involves creating config maps in helm '
         'charts with overides (sound familiar?)')

    run_shell(args,
              'cd kolla-kubernetes; sudo ansible-playbook -e '
              'ansible_python_interpreter=/usr/bin/python -e '
              '@/etc/kolla/globals.yml -e @/etc/kolla/passwords.yml '
              '-e CONFIG_DIR=/etc/kolla ./ansible/site.yml; cd ..')


def kolla_gen_secrets(args):
    '''Generate Kubernetes secrets'''

    print_progress('Kolla',
                   'Generate secrets and register them with Kubernetes',
                   KOLLA_FINAL_PROGRESS)

    demo(args,
         'Create secrets from the generated password file using '
         '"kubectl create secret generic"',
         'Kubernetes Secrets is an object that contains a small amount of\n'
         'sensitive data such as passwords, keys and tokens etc')

    run_shell(args,
              'python ./kolla-kubernetes/tools/secret-generator.py create')


def kolla_create_config_maps(args):
    '''Generate the Kolla config map'''

    print_progress('Kolla',
                   'Generate and register the Kolla config maps',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Create Kolla Config Maps',
         'Similar to Secrets, Config Maps are another kubernetes artifact\n'
         'ConfigMaps allow you to decouple configuration '
         'artifacts from image\n'
         'content to keep containerized applications portable. '
         'The ConfigMap API\n'
         'resource stores configuration data as key-value pairs. '
         'The data can be\n'
         'consumed in pods or provide the configurations for '
         'system components\n'
         'such as controllers. ConfigMap is similar to Secrets, '
         'but provides a\n'
         'means of working with strings that do not contain '
         'sensitive information.\n'
         'Users and system components alike can store configuration '
         'data in ConfigMap.')
    run_shell(args,
              'kollakube res create configmap '
              'mariadb keystone horizon rabbitmq memcached nova-api '
              'nova-conductor nova-scheduler glance-api-haproxy '
              'glance-registry-haproxy glance-api glance-registry '
              'neutron-server neutron-dhcp-agent neutron-l3-agent '
              'neutron-metadata-agent neutron-openvswitch-agent '
              'openvswitch-db-server openvswitch-vswitchd nova-libvirt '
              'nova-compute nova-consoleauth nova-novncproxy '
              'nova-novncproxy-haproxy neutron-server-haproxy '
              'nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup '
              'cinder-scheduler cinder-volume iscsid tgtd keepalived '
              'placement-api placement-api-haproxy')

    demo(args, 'Lets look at a configmap',
         'kubectl get configmap -n kolla; kubectl describe '
         'configmap -n kolla XYZ')


def kolla_build_micro_charts(args):
    '''Build all helm micro charts'''

    print_progress('Kolla',
                   'Build and register all Helm charts (Slow!)',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Build helm charts',
         'Helm uses a packaging format called charts. '
         'A chart is a collection of\n'
         'files that describe a related set of Kubernetes '
         'resources. A single chart\n'
         'might be used to deploy something simple, like a'
         'memcached pod, or something\n'
         'complex, like a full web app stack with HTTP servers, '
         'databases, caches, and so on\n'
         'Helm also allows you to detail dependencies between '
         'charts - vital for Openstack\n'
         'This step builds all the known helm charts and '
         'dependencies (193)\n'
         'This is another step that takes a few minutes')
    if args.demo:
        print(run_shell(
            args,
            './kolla-kubernetes/tools/helm_build_all.sh /tmp'))
    else:
        run_shell(
            args,
            './kolla-kubernetes/tools/helm_build_all.sh /tmp')

    demo(args, 'Lets look at these helm charts',
         'helm list; helm search | grep local | wc -l; '
         'helm fetch url chart; helm inspect local/glance')


def kolla_verify_helm_images(args):
    '''Check to see if enough helm charts were generated'''

    print_progress('Kolla',
                   'Verify number of helm images',
                   KOLLA_FINAL_PROGRESS)

    out = run_shell(args, 'ls /tmp | grep ".tgz" | wc -l')
    if int(out) > 190:
        print('  %s Helm images created' % int(out))
    else:
        print('  Error: only %s Helm images created' % int(out))
        sys.exit(1)


def kolla_create_cloud_v4(args):
    '''Generate the cloud.yml file

    Which works with the globals.yml file to define your cluster networking.

    This uses most of the user options.

    This works for tag version 4.x
    '''

    print_progress('Kolla',
                   'Create a version 4 cloud.yaml',
                   KOLLA_FINAL_PROGRESS)

    demo(args, 'Create a 4.x (Ocata) cloud.yaml',
         'cloud.yaml is the partner to globals.yml\n'
         'It contains a list of global OpenStack services '
         'and key-value pairs, which\n'
         'guide helm when running each chart. This includes '
         'our basic inputs, MGMT and Neutron')
    cloud = '/tmp/cloud.yaml'
    with open(cloud, "w") as w:
        w.write("""
global:
   kolla:
     all:
       image_tag: "%s"
       kube_logger: false
       external_vip: "%s"
       base_distro: "%s"
       install_type: "source"
       tunnel_interface: "%s"
       kolla_kubernetes_external_subnet: 24
       kolla_kubernetes_external_vip: %s
     keepalived:
       all:
         api_interface: br-ex
     keystone:
       all:
         admin_port_external: "true"
         dns_name: "%s"
         port: 5000
       public:
         all:
           port_external: "true"
     rabbitmq:
       all:
         cookie: 67
     glance:
       api:
         all:
           port_external: "true"
     cinder:
       api:
         all:
           port_external: "true"
       volume_lvm:
         all:
           element_name: cinder-volume
         daemonset:
           lvm_backends:
           - '%s': 'cinder-volumes'
     ironic:
       conductor:
         daemonset:
           selector_key: "kolla_conductor"
     nova:
       placement_api:
         all:
           port_external: true
       novncproxy:
         all:
           port: 6080
           port_external: true
     openvwswitch:
       all:
         add_port: true
         ext_bridge_name: br-ex
         ext_interface_name: %s
         setup_bridge: true
     horizon:
       all:
         port_external: true
        """ % (kolla_get_image_tag(args),
               args.mgmt_ip,
               args.base_distro,
               args.MGMT_INT,
               args.vip_ip,
               args.mgmt_ip,
               args.mgmt_ip,
               args.NEUTRON_INT))

    if args.edit_cloud:
        pause_tool_execution('Pausing to edit the /tmp/cloud.yaml file')

    if args.demo:
        print(run_shell(args, 'sudo cat /tmp/cloud.yaml'))


def kolla_create_cloud(args):
    '''Generate the cloud.yml file

    Which works with the globals.yml file to define your cluster networking.

    This uses most of the user options.

    This works for tag versions 5+
    '''

    # Note for local registry add "docker_registry: 127.0.0.1:30401"

    print_progress('Kolla',
                   'Create a version 5+ cloud.yaml',
                   KOLLA_FINAL_PROGRESS)

    image_tag = kolla_get_image_tag(args)

    demo(args, 'Create a 5.x (Pike) cloud.yaml',
         'cloud.yaml is the partner to globals.yml\n'
         'It contains a list of global OpenStack services '
         'and key-value pairs, which\n'
         'guide helm when running each chart. This includes our '
         'basic inputs, MGMT and Neutron')
    cloud = '/tmp/cloud.yaml'
    with open(cloud, "w") as w:
        w.write("""
global:
   kolla:
     all:
       docker_namespace: %s
       image_tag: "%s"
       kube_logger: false
       external_vip: "%s"
       base_distro: "%s"
       install_type: source
       tunnel_interface: "%s"
       ceph_backend: false
       libvirt_tcp: false
       kolla_kubernetes_external_subnet: 24
       kolla_kubernetes_external_vip: %s
       kolla_toolbox_image_tag: %s
       haproxy_image_tag: %s
       fluentd_image_tag: %s
       kubernetes_entrypoint_image_tag: %s
     keepalived:
       all:
         api_interface: br-ex
     keystone:
       all:
         admin_port_external: "true"
         dns_name: "%s"
         port: 5000
       public:
         all:
           port_external: "true"
     rabbitmq:
       all:
         cookie: 67
     glance:
       api:
         all:
           port_external: "true"
     cinder:
       api:
         all:
           port_external: "true"
       volume_lvm:
         all:
           element_name: cinder-volume
         daemonset:
           lvm_backends:
           - '%s': 'cinder-volumes'
     nova:
       all:
         placement_api_enabled: true
         cell_enabled: true
       novncproxy:
         all:
           port: 6080
           port_external: true
       api:
         create_cell:
           job:
             cell_wait_compute: false
     ironic:
       conductor:
         daemonset:
           selector_key: "kolla_conductor"
     openvwswitch:
       all:
         add_port: true
         ext_bridge_name: br-ex
         ext_interface_name: %s
         setup_bridge: true
     horizon:
       all:
         port_external: true
        """ % (args.docker_repo,
               image_tag,
               args.mgmt_ip,
               args.base_distro,
               args.MGMT_INT,
               args.vip_ip,
               image_tag,
               image_tag,
               image_tag,
               image_tag,
               args.mgmt_ip,
               args.mgmt_ip,
               args.NEUTRON_INT))

    if args.edit_cloud:
        pause_tool_execution('Pausing to edit the /tmp/cloud.yaml file')

    if args.demo:
        print(run_shell(args, 'sudo cat /tmp/cloud.yaml'))


def helm_install_service_chart(args, chart_list):
    '''helm install a list of service charts'''

    for chart in chart_list:
        print_progress('Kolla',
                       "Helm Install service chart: \--'%s'--/" % chart,
                       KOLLA_FINAL_PROGRESS)
        run_shell(args,
                  'helm install --debug kolla-kubernetes/helm/service/%s '
                  '--namespace kolla --name %s --values /tmp/cloud.yaml'
                  % (chart, chart))
        k8s_wait_for_pod_start(args, chart)
    k8s_wait_for_running_negate(args)


def helm_install_micro_service_chart(args, chart_list):
    '''helm install a list of micro service charts'''

    for chart in chart_list:
        print_progress('Kolla',
                       "Helm Install micro service chart: \--'%s'--/" % chart,
                       KOLLA_FINAL_PROGRESS)
        run_shell(args,
                  'helm install --debug kolla-kubernetes/helm/microservice/%s '
                  '--namespace kolla --name %s --values /tmp/cloud.yaml'
                  % (chart, chart))
    k8s_wait_for_running_negate(args)


def kolla_create_keystone_user(args):
    '''Create a keystone user'''

    demo(args, 'We now should have a running OpenStack Cluster on Kubernetes!',
         'Lets create a keystone account, create a demo VM, '
         'attach a floating ip\n'
         'Finally ssh to the VM and or open Horizon and '
         'see our cluster')

    print_progress('Kolla',
                   'Create a keystone admin account',
                   KOLLA_FINAL_PROGRESS)

    run_shell(args, 'sudo rm -f ~/keystonerc_admin')
    run_shell(args,
              'kolla-kubernetes/tools/build_local_admin_keystonerc.sh ext')


def kolla_allow_ingress(args):
    '''Open up ingress rules to access vm'''

    print_progress('Kolla',
                   'Allow Ingress by changing neutron rules',
                   KOLLA_FINAL_PROGRESS)

    new = '/tmp/neutron_rules.sh'
    with open(new, "w") as w:
        w.write("""
openstack security group list -f value -c ID | while read SG_ID; do
    neutron security-group-rule-create --protocol icmp \
        --direction ingress $SG_ID
    neutron security-group-rule-create --protocol tcp \
        --port-range-min 22 --port-range-max 22 \
        --direction ingress $SG_ID
done
""")
    out = run_shell(args,
                    '.  ~/keystonerc_admin; chmod 766 %s; bash %s' %
                    (new, new))
    logger.debug(out)


def kolla_pike_workaround(args):
    '''An issue in Pike with nova that needs to be fixed

    I believe this is because we are using the simple cell setup which is
    really an upgrade scenario. Kolla-Ansible does not do this.

    https://docs.openstack.org/nova/latest/user/cells.html#step-by-step-for-common-use-cases

    The chart jobs are commented out below but that didn't fix it for me.
    '''

    if not re.search('ocata', args.image_version):
        print_progress('Kolla',
                       'Fix Nova, various issues, nova scheduler pod '
                       'will be restarted',
                       KOLLA_FINAL_PROGRESS)

        # todo: get these jobs to work
        # chart_list = ['nova-cell0-create-db-job']
        # helm_install_micro_service_chart(args, chart_list)

        # chart_list = ['nova-api-create-simple-cell-job']
        # helm_install_micro_service_chart(args, chart_list)

        run_shell(args,
                  'kubectl exec -it nova-conductor-0 -n kolla '
                  'nova-manage db sync')
        run_shell(args,
                  'kubectl exec -it nova-conductor-0 -n kolla '
                  'nova-manage cell_v2 discover_hosts')
        run_shell(args,
                  'kubectl delete pod nova-scheduler-0 -n kolla')
        k8s_wait_for_running_negate(args)


def kolla_get_host_subnet(args):
    '''Grab an address to access a demo vm

    Return the subnet, actual ip address and the last octet to start the DHCP
    range
    '''

    # Grab default route
    default = run_shell(
        args,
        "ip route | grep default | grep %s | awk '{ print $3 }'" %
        args.MGMT_INT)
    subnet = default[:default.rfind(".")]
    r = list(range(2, 253))
    random.shuffle(r)
    for k in r:
        vip = run_shell(args, 'sudo nmap -sP -PR %s.%s' % (subnet, k))
        if "Host seems down" in vip:
            ip = subnet + '.' + str(k)
            break
    return(subnet, ip, k)


def kolla_get_mgmt_subnet(args):
    '''Grab an address to access a demo vm

    Return the subnet, actual ip address and the last octet to start the DHCP
    range
    '''

    subnet = args.mgmt_ip[:args.mgmt_ip.rfind(".")]
    r = list(range(2, 253))
    random.shuffle(r)
    for k in r:
        vip = run_shell(args, 'sudo nmap -sP -PR %s.%s' % (subnet, k))
        if "Host seems down" in vip:
            ip = subnet + '.' + str(k)
            break
    return(subnet, ip, k)


def kolla_get_neutron_subnet(args):
    '''Find and return a neutron ip address

    That can be used for the neutron subnet

    Because the neutron interface does not have an ip address. Briefly ask
    DHCP for one, then release it after extracting the lease
    '''

    # -v -r doesn't seem to work - so run seperately
    run_shell(args,
              'sudo dhclient %s -v > /tmp/dhcp 2>&1' %
              args.NEUTRON_INT)

    run_shell(args,
              'sudo dhclient %s -r > /tmp/dhcp_r 2>&1' %
              args.NEUTRON_INT)

    out = run_shell(
        args,
        "cat /tmp/dhcp | grep -i 'bound to ' | awk '{ print $3 }'")

    if out is None:
        print('Kolla - no neutron subnet found, continuing but \
        openstack likely not healthy')

    subnet = out[:out.rfind(".")]
    r = list(range(2, 253))
    random.shuffle(r)
    for k in r:
        vip = run_shell(args, 'sudo nmap -sP -PR %s.%s' % (subnet, k))
        if "Host seems down" in vip:
            out = subnet + '.' + str(k)
            break
    return(subnet, out, k)


def kolla_setup_neutron(args):
    '''Use kolla-ansible init-runonce logic but with correct networking'''

    neutron_subnet, neutron_start, octet = kolla_get_neutron_subnet(args)
    # neutron_subnet, neutron_start, octet = kolla_get_host_subnet(args)
    EXT_NET_CIDR = neutron_subnet + '.' + '0' + '/' + '24'
    EXT_NET_GATEWAY = neutron_subnet + '.' + '1'
    # Because I don't own these - only use one that I know is safe
    neutron_end = octet + 10
    EXT_NET_RANGE = 'start=%s,end=%s' % (
        neutron_start, neutron_subnet + '.' + str(neutron_end))

    if args.dev_mode:
        print('DEV: CIDR=%s, GW=%s, range=%s' %
              (EXT_NET_CIDR, EXT_NET_GATEWAY, EXT_NET_RANGE))

    runonce = './runonce'
    with open(runonce, "w") as w:
        w.write("""
#!/bin/bash
#
# This script is meant to be run once after running start for the first
# time.  This script downloads a cirros image and registers it.  Then it
# configures networking and nova quotas to allow 40 m1.small instances
# to be created.

IMAGE_URL=http://download.cirros-cloud.net/0.4.0/
IMAGE=cirros-0.4.0-x86_64-disk.img
IMAGE_NAME=cirros
IMAGE_TYPE=linux
EXT_NET_CIDR='%s'
EXT_NET_RANGE='%s'
EXT_NET_GATEWAY='%s'

# Sanitize language settings to avoid commands bailing out
# with "unsupported locale setting" errors.
unset LANG
unset LANGUAGE
LC_ALL=C
export LC_ALL
for i in curl openstack; do
    if [[ ! $(type ${i} 2>/dev/null) ]]; then
        if [ "${i}" == 'curl' ]; then
            echo "Please install ${i} before proceeding"
        else
            echo "Please install python-${i}client before proceeding"
        fi
        exit
    fi
done
# Move to top level directory
REAL_PATH=$(python -c "import os,sys;print os.path.realpath('$0')")
cd "$(dirname "$REAL_PATH")/.."

# Test for credentials set
if [[ "${OS_USERNAME}" == "" ]]; then
    echo "No Keystone credentials specified.  Try running source openrc"
    exit
fi

# Test to ensure configure script is run only once
if openstack image list | grep -q cirros; then
    echo "This tool should only be run once per deployment."
    exit
fi

if ! [ -f "${IMAGE}" ]; then
    curl -L -o ./${IMAGE} ${IMAGE_URL}/${IMAGE}
fi

openstack image create --disk-format qcow2 --container-format bare --public \
    --property os_type=${IMAGE_TYPE} --file ./${IMAGE} ${IMAGE_NAME}

openstack network create --external --provider-physical-network physnet1 \
    --provider-network-type flat public1

# Create a subnet to provider network
openstack subnet create --dhcp \
    --allocation-pool ${EXT_NET_RANGE} --network public1 \
    --subnet-range ${EXT_NET_CIDR} --gateway ${EXT_NET_GATEWAY} public1-subnet

openstack network create --provider-network-type vxlan demo-net
openstack subnet create --subnet-range 10.0.0.0/24 --network demo-net \
    --gateway 10.0.0.1 --dns-nameserver 8.8.8.8 demo-subnet

openstack router create demo-router
openstack router add subnet demo-router demo-subnet
openstack router set --external-gateway public1 demo-router

# Get admin user and tenant IDs
ADMIN_USER_ID=$(openstack user list | awk '/ admin / {print $2}')
ADMIN_PROJECT_ID=$(openstack project list | awk '/ admin / {print $2}')
ADMIN_SEC_GROUP=$(openstack security group list --project \
        ${ADMIN_PROJECT_ID} | awk '/ default / {print $2}')

# Sec Group Config
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol icmp ${ADMIN_SEC_GROUP}
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol tcp --dst-port 22 ${ADMIN_SEC_GROUP}
# Open heat-cfn so it can run on a different host
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol tcp --dst-port 8000 ${ADMIN_SEC_GROUP}
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol tcp --dst-port 8080 ${ADMIN_SEC_GROUP}

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -f ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa.pub
fi
if [ -r ~/.ssh/id_rsa.pub ]; then
    openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
fi

# Increase the quota to allow 40 m1.small instances to be created

# 40 instances
openstack quota set --instances 40 ${ADMIN_PROJECT_ID}

# 40 cores
openstack quota set --cores 40 ${ADMIN_PROJECT_ID}

# 96GB ram
openstack quota set --ram 96000 ${ADMIN_PROJECT_ID}

# add default flavors, if they don't already exist
if ! openstack flavor list | grep -q m1.tiny; then
    openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny
    openstack flavor create --id 2 --ram 2048 --disk 20 --vcpus 1 m1.small
    openstack flavor create --id 3 --ram 4096 --disk 40 --vcpus 2 m1.medium
    openstack flavor create --id 4 --ram 8192 --disk 80 --vcpus 4 m1.large
    openstack flavor create --id 5 --ram 16384 --disk 160 --vcpus 8 m1.xlarge
fi

DEMO_NET_ID=$(openstack network list | awk '/ public1 / {print $2}')

cat << EOF

Done.

To deploy a demo instance, run:

openstack server create \\
    --image ${IMAGE_NAME} \\
    --flavor m1.tiny \\
    --key-name mykey \\
    --nic net-id=${DEMO_NET_ID} \\
    demo1
EOF
        """ % (EXT_NET_CIDR, EXT_NET_RANGE, EXT_NET_GATEWAY))


def kolla_nw_and_images(args):
    '''Final steps now that a working cluster is up.

    Run "runonce" to set everything up.
    Install a demo image.
    Attach a floating ip.
    '''

    if args.no_network:
        return

    kolla_setup_neutron(args)

    print_progress('Kolla',
                   'Configure Neutron, pull images',
                   KOLLA_FINAL_PROGRESS)

    out = run_shell(
        args,
        '.  ~/keystonerc_admin; chmod 777 ./runonce; ./runonce')
    logger.debug(out)

    demo_net_id = run_shell(
        args,
        ".  ~/keystonerc_admin; "
        "echo $(openstack network list | awk '/ public1 / {print $2}')")
    logger.debug(demo_net_id)

    # Create a demo image
    print_progress('Kolla',
                   'Create a demo VM in our OpenStack cluster',
                   KOLLA_FINAL_PROGRESS)

    create_demo_vm = '  .  ~/keystonerc_admin; openstack server ' \
        'create --image cirros --flavor m1.tiny --key-name mykey ' \
        '--nic net-id=%s test' % demo_net_id.rstrip()
    print('  To create a demo image VM do:')
    print(create_demo_vm)

    # For now, only suggest a demo VM and floating ip
    #
    out = run_shell(args,
                    '.  ~/keystonerc_admin; openstack server create '
                    '--image cirros --flavor m1.tiny --key-name mykey '
                    '--nic net-id=%s demo1' % demo_net_id.rstrip())
    logger.debug(out)
    k8s_wait_for_vm(args, 'demo1')

    # Create a floating ip
    print_progress('Kolla',
                   'Create floating IP',
                   KOLLA_FINAL_PROGRESS)

    cmd = ".  ~/keystonerc_admin; \
    openstack server add floating ip demo1 $(openstack floating ip \
    create public1 -f value -c floating_ip_address)"
    out = run_shell(args, cmd)
    logger.debug(out)

    # Display nova list
    print_progress('Kolla',
                   'Demo VM Info',
                   KOLLA_FINAL_PROGRESS)

    print(run_shell(args, '.  ~/keystonerc_admin; nova list'))
    # todo: ssh execute to ip address and ping google


def kolla_final_messages(args):
    '''Setup horizon and print success message'''

    address = run_shell(args, "kubectl get svc horizon --namespace kolla "
                        "--no-headers | awk '{print $3}'")
    username = run_shell(
        args,
        "cat ~/keystonerc_admin | grep OS_PASSWORD | awk '{print $2}'")
    password = run_shell(
        args,
        "cat ~/keystonerc_admin | grep OS_USERNAME | awk '{print $2}'")

    print_progress('Kolla',
                   'To Access Horizon:',
                   KOLLA_FINAL_PROGRESS)

    print('  Point your browser to: %s' % address)
    print('  %s' % username)
    print('  %s' % password)

    banner('Successfully deployed Kolla-Kubernetes. '
           'OpenStack Cluster is ready for use')


def k8s_test_vip_int(args):
    '''Test that the vip interface is not used'''

    # Allow the vip address to be the same as the mgmt_ip
    if args.vip_ip != args.mgmt_ip:
        truth = run_shell(
            args,
            'sudo nmap -sP -PR %s | grep Host' %
            args.vip_ip)
        if re.search('Host is up', truth):
            print('Kubernetes - vip Interface %s is in use, '
                  'choose another' % args.vip_ip)
            sys.exit(1)
        else:
            logger.debug(
                'Kubernetes - VIP Keepalive Interface %s is valid' %
                args.vip_ip)


def k8s_get_pods(args, namespace):
    '''Display all pods per namespace list'''

    for name in namespace:
        final = run_shell(args, 'kubectl get pods -n %s' % name)

        print_progress('Kolla',
                       'Final Kolla Kubernetes OpenStack '
                       'pods for namespace %s:' % name,
                       KOLLA_FINAL_PROGRESS)

        print(final)


def k8s_check_nslookup(args):
    '''Create a test pod and query nslookup against kubernetes

    Only seems to work in the default namespace

    Also handles the option to create a test pod manually like
    the deployment guide advises.
    '''

    print_progress('Kubernetes',
                   "Test 'nslookup kubernetes' - bring up test pod",
                   K8S_FINAL_PROGRESS)

    demo(args, 'Lets create a simple pod and verify that DNS works',
         'If it does not then this deployment will not work.')
    name = './busybox.yaml'
    with open(name, "w") as w:
        w.write("""
apiVersion: v1
kind: Pod
metadata:
  name: kolla-dns-test
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
""")
    demo(args, 'The busy box yaml is: %s' % name, '')
    if args.demo:
        print(run_shell(args, 'sudo cat ./busybox.yaml'))

    run_shell(args, 'kubectl create -f %s' % name)
    k8s_wait_for_running_negate(args)
    out = run_shell(args,
                    'kubectl exec kolla-dns-test -- nslookup '
                    'kubernetes | grep -i address | wc -l')
    demo(args, 'Kolla DNS test output: "%s"' % out, '')
    if int(out) != 2:
        print("  Warning 'nslookup kubernetes ' failed. YMMV continuing")
    else:
        banner("Kubernetes Cluster is up and running")


def kubernetes_test_cli(args):
    '''Run some commands for demo purposes'''

    if not args.demo:
        return

    demo(args, 'Test CLI:', 'Determine IP and port information from Service:')
    print(run_shell(args, 'kubectl get svc -n kube-system'))
    print(run_shell(args, 'kubectl get svc -n kolla'))

    demo(args, 'Test CLI:', 'View all k8s namespaces:')
    print(run_shell(args, 'kubectl get namespaces'))

    demo(args, 'Test CLI:', 'Kolla Describe a pod in full detail:')
    print(run_shell(args, 'kubectl describe pod ceph-admin -n kolla'))

    demo(args, 'Test CLI:', 'View all deployed services:')
    print(run_shell(args, 'kubectl get deployment -n kube-system'))

    demo(args, 'Test CLI:', 'View configuration maps:')
    print(run_shell(args, 'kubectl get configmap -n kube-system'))

    demo(args, 'Test CLI:', 'General Cluster information:')
    print(run_shell(args, 'kubectl cluster-info'))

    demo(args, 'Test CLI:', 'View all jobs:')
    print(run_shell(args, 'kubectl get jobs --all-namespaces'))

    demo(args, 'Test CLI:', 'View all deployments:')
    print(run_shell(args, 'kubectl get deployments --all-namespaces'))

    demo(args, 'Test CLI:', 'View secrets:')
    print(run_shell(args, 'kubectl get secrets'))

    demo(args, 'Test CLI:', 'View docker images')
    print(run_shell(args, 'sudo docker images'))

    demo(args, 'Test CLI:', 'View deployed Helm Charts')
    print(run_shell(args, 'helm list'))

    demo(args, 'Test CLI:', 'Working cluster kill a pod and watch resilience.')
    demo(args, 'Test CLI:', 'kubectl delete pods <name> -n kolla')


def k8s_bringup_kubernetes_cluster(args):
    '''Bring up a working Kubernetes Cluster

    Explicitly using the Canal CNI for now
    '''

    if args.openstack:
        print('Kolla - Building OpenStack on existing Kubernetes cluster')
        return

    k8s_cleanup(args)
    k8s_install_tools(args)
    k8s_setup_ntp(args)
    k8s_turn_things_off(args)
    k8s_install_k8s(args)
    if args.create_minion:
        run_shell(args, 'sudo systemctl enable kubelet.service')
        run_shell(args, 'sudo systemctl enable docker.service')
        run_shell(args, 'sudo systemctl start docker.service')
        banner('Kubernetes tools installed, minion ready')
        sys.exit(1)
    k8s_setup_dns(args)
    k8s_reload_service_files(args)
    k8s_start_kubelet(args)
    k8s_fix_iptables(args)
    k8s_deploy_k8s(args)
    k8s_load_kubeadm_creds(args)
    k8s_wait_for_kube_system(args)
    k8s_add_api_server(args)
    k8s_deploy_cni(args)
    k8s_wait_for_pod_start(args, 'canal')
    k8s_wait_for_running_negate(args)
    k8s_schedule_master_node(args)
    k8s_check_nslookup(args)
    k8s_check_exit(args.kubernetes)
    demo(args, 'Congrats - your kubernetes cluster should be up '
         'and running now', '')


def kolla_get_image_tag(args):
    '''Set the image tag

    In most cases the image tag is now the same as the image version.
    For example, ocata = ocata.

    But for self-built images, then we need an image tag as that is specified
    or generated by kolla build tool.

    So if user has entered an image tag - use it.
    '''

    if args.image_tag:
        return(args.image_tag)
    else:
        return(args.image_version)


def kolla_install_logging(args):
    '''Install log collection

    Experimental to test out various centralized logging options

    https://github.com/kubernetes/charts/blob/master/stable/fluent-bit/values.yaml

    Kafka can be added, but it's only available in a dev image.

    repository: fluent/fluent-bit-kafka-dev
    tag: 0.4

    Note that both changes to the forwarder and kafka require changes to
    the helm chart.
    '''

    if not args.logs:
        return

    name = '/tmp/fluentd_values.yaml'
    with open(name, "w") as w:
        w.write("""\
# Minikube stores its logs in a seperate directory.
# enable if started in minikube.
on_minikube: false

image:
  fluent_bit:
    repository: fluent/fluent-bit
    tag: 0.12.10
  pullPolicy: Always

backend:
  type: forward
  forward:
    host: fluentd
    port: 24284
  es:
    host: elasticsearch
    port: 9200
  kafka:
    # See dev image note above
    host: kafka
    port: 9092
    topics: test
    brokers: kafka:9092

env: []

resources:
  limits:
    memory: 100Mi
  requests:
    cpu: 100m
    memory: 100Mi

# Node tolerations for fluent-bit scheduling to nodes with taints
# Ref: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/
##
tolerations: []
#- key: "key"
#  operator: "Equal|Exists"
#  value: "value"
#  effect: "NoSchedule|PreferNoSchedule|NoExecute(1.6 only)"

# Node labels for fluent-bit pod assignment
# Ref: https://kubernetes.io/docs/user-guide/node-selection/
##
nodeSelector: {}
""")

    print_progress('Kolla',
                   'Install fluent-bit log aggregator',
                   KOLLA_FINAL_PROGRESS)
    run_shell(args,
              'helm install --name my-release -f %s '
              'stable/fluent-bit' % name)
    k8s_wait_for_running_negate(args)


def kolla_bring_up_openstack(args):
    '''Install OpenStack with Kolla'''

    global KOLLA_FINAL_PROGRESS

    banner('Kolla - build and prepare OpenStack')
    clean_progress()
    # Start Kolla deployment
    add_one_to_progress()
    kolla_update_rbac(args)
    kolla_install_deploy_helm(args)
    kolla_install_repos(args)
    kolla_setup_loopback_lvm(args)
    kolla_install_os_client(args)
    kolla_gen_passwords(args)
    kolla_create_namespace(args)

    node_list = ['kolla_compute', 'kolla_controller']
    kolla_label_nodes(args, node_list)
    kolla_modify_globals(args)
    kolla_add_to_globals(args)
    kolla_gen_configs(args)
    kolla_enable_qemu(args)
    kolla_gen_secrets(args)
    kolla_create_config_maps(args)
    kolla_build_micro_charts(args)
    kolla_verify_helm_images(args)

    if 'ocata' in args.image_version:
        kolla_create_cloud_v4(args)
    else:
        kolla_create_cloud(args)

    banner('Kolla - deploy OpenStack:')

    # Set up OVS for the Infrastructure
    chart_list = ['openvswitch']
    demo(args, 'Install %s Helm Chart' % chart_list, '')
    helm_install_service_chart(args, chart_list)

    # Bring up br-ex for keepalived to bind VIP to it
    run_shell(args, 'sudo ifconfig br-ex up')

    # chart_list = ['keepalived-daemonset']
    # demo(args, 'Install %s Helm Chart' % chart_list, '')
    # helm_install_micro_service_chart(args, chart_list)

    # Install Helm charts
    chart_list = ['mariadb']
    demo(args, 'Install %s Helm Chart' % chart_list, '')
    helm_install_service_chart(args, chart_list)

    # Install remaining service level charts
    chart_list = ['rabbitmq', 'memcached', 'keystone', 'glance',
                  'cinder-control', 'cinder-volume-lvm', 'horizon',
                  'neutron']
    demo(args, 'Install %s Helm Chart' % chart_list, '')
    helm_install_service_chart(args, chart_list)

    chart_list = ['nova-control', 'nova-compute']
    demo(args, 'Install %s Helm Chart' % chart_list, '')
    helm_install_service_chart(args, chart_list)

    # Add v3 keystone end points
    if args.dev_mode:
        if not re.search('ocata', args.image_version):
            print_progress('Kolla',
                           'Install Cinder V3 API',
                           KOLLA_FINAL_PROGRESS)

            chart_list = ['cinder-create-keystone-endpoint-adminv3-job',
                          'cinder-create-keystone-endpoint-internalv3-job',
                          'cinder-create-keystone-endpoint-publicv3-job',
                          'cinder-create-keystone-servicev3-job']
            helm_install_micro_service_chart(args, chart_list)

            # Restart horizon pod to get new api endpoints
            horizon = run_shell(
                args,
                "kubectl get pods --all-namespaces | grep horizon "
                "| awk '{print $2}'")
            run_shell(args,
                      'kubectl delete pod %s -n kolla' % horizon)
            k8s_wait_for_running_negate(args)

            # Some updates needed to cinderclient
            horizon = run_shell(
                args,
                "sudo docker ps | grep horizon | grep kolla_start "
                "| awk '{print $1}'")
            run_shell(args,
                      'sudo docker exec -tu root -i %s pip install --upgrade '
                      'python-cinderclient' % horizon)

            cinder = run_shell(args,
                               "sudo docker ps | grep cinder-volume | "
                               "grep kolla_start | awk '{print $1}'")
            run_shell(args,
                      'sudo docker exec -tu root -i %s pip install --upgrade '
                      'python-cinderclient' % cinder)

    # Install logging container
    kolla_install_logging(args)

    namespace_list = ['kube-system', 'kolla']
    k8s_get_pods(args, namespace_list)


def main():
    '''Main function.'''

    args = parse_args()

    # Force sudo early on
    run_shell(args, 'sudo -v')

    # Populate IP Addresses
    populate_ip_addresses(args)

    if args.dev_mode:
        subnet, start, octet = kolla_get_host_subnet(args)
        print('DEV: HOST: subnet=%s, start=%s' %
              (subnet, start))
        subnet, start, octet = kolla_get_mgmt_subnet(args)
        print('DEV: MGMT: sub<net=%s, start=%s' %
              (subnet, start))
        if not args.no_network:
            subnet, start, octet = kolla_get_neutron_subnet(args)
            print('DEV: NTRN: subnet=%self, start=%s' %
                  (subnet, start))

    #
    # Setup globals
    #

    # Start progress on one
    add_one_to_progress()

    global KOLLA_FINAL_PROGRESS
    if re.search('5.', kolla_get_image_tag(args)):
        # Add one for additional docker registry pod bringup
        KOLLA_FINAL_PROGRESS = 46
    else:
        KOLLA_FINAL_PROGRESS = 45

    if args.no_network:
        KOLLA_FINAL_PROGRESS -= 4

    if args.no_git:
        KOLLA_FINAL_PROGRESS -= 1

    global K8S_CLEANUP_PROGRESS
    if os.path.exists('/data'):
        # Add one if we need to clean up LVM
        K8S_CLEANUP_PROGRESS = 7
    else:
        K8S_CLEANUP_PROGRESS = 6

    # Ubuntu does not need the selinux step
    global K8S_FINAL_PROGRESS
    if linux_ver() == 'centos':
        K8S_FINAL_PROGRESS = 16
    else:
        K8S_FINAL_PROGRESS = 15

    if args.create_minion:
        K8S_FINAL_PROGRESS = 5

    set_logging()
    logger.setLevel(level=args.verbose)

    if args.complete_cleanup is not True:
        print_versions(args)

    try:
        if args.complete_cleanup:
            k8s_cleanup(args)
            sys.exit(1)

        k8s_test_vip_int(args)
        k8s_bringup_kubernetes_cluster(args)
        kolla_bring_up_openstack(args)
        kolla_create_keystone_user(args)
        kolla_allow_ingress(args)
        kolla_pike_workaround(args)
        kolla_nw_and_images(args)
        kolla_final_messages(args)
        kubernetes_test_cli(args)

    except Exception:
        print('Exception caught:')
        print(sys.exc_info())
        raise


if __name__ == '__main__':
    main()
