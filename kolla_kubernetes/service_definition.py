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


import os.path

from oslo_config import cfg
from oslo_log import log

from kolla_kubernetes.common import file_utils
from kolla_kubernetes import exception

CONF = cfg.CONF
CNF_FIELDS = ('source', 'dest', 'owner', 'perm')
CMD_FIELDS = ('run_once', 'dependencies', 'command', 'env',
              'delay', 'retries', 'files')
DEP_FIELDS = ('path', 'scope')
SCOPE_OPTS = ('global', 'local')
LOG = log.getLogger()

# TODO(rhallisey): make pod definitions dynamic
# The pods associated with a service
POD_DEFINITIONS = {'mariadb': ['mariadb'],
                   'memcached': ['memcached'],
                   'rabbitmq': ['rabbitmq'],
                   'keystone': ['keystone'],
                   'glance': ['glance'],
                   'nova': ['nova-compute', 'nova-control'],
                   'neutron': ['neutron-compute', 'neutron-control',
                               'neutron-network'],
                   'swift': ['swift-account', 'swift-container',
                             'swift-object', 'swift-proxy']}

# TODO(rhallisey): make container definitions dynamic
# The containers in a pod
CONTAINER_DEFINITIONS = {'mariadb': ['mariadb'],
                         'memcached': ['memcached'],
                         'rabbitmq': ['rabbitmq'],
                         'keystone': ['keystone'],
                         'glance': ['glance-api', 'glance-registry'],
                         'nova-compute': ['nova-compute', 'nova-libvirt'],
                         'nova-control': ['nova-api', 'nova-scheduler',
                                          'nova-conductor'],
                         'neutron-compute': ['openvswitch-db-server',
                                             'openvswitch-vswitchd',
                                             'neutron-openvswitch-agent',
                                             'neutron-linuxbridge-agent'],
                         'neutron-network': ['neutron-l3-agent',
                                             'neutron-dhcp-agent',
                                             'neutron-medadata-agent'],
                         'neutron-control': ['neutron-server'],
                         'swift-account': ['swift-rsyncd',
                                           'swift-account-server',
                                           'swift-account-auditor',
                                           'swift-account-replicator',
                                           'swift-account-reaper'],
                         'swift-container': ['swift-rsyncd',
                                             'swift-container-server',
                                             'swift-container-auditor',
                                             'swift-container-replicator',
                                             'swift-container-updater'],
                         'swift-object': ['swift-rsyncd',
                                          'swift-object-server',
                                          'swift-object-auditor',
                                          'swift-object-replicator',
                                          'swift-object-updater',
                                          'swift-object-expirer'],
                         'swift-proxy': ['swift-proxy-server']}


def get_pod_definition(service):
    return POD_DEFINITIONS[service]


def get_container_definition(container):
    return CONTAINER_DEFINITIONS[container]


def get_services_directory():
    return (CONF.service_dir or
            os.path.join(file_utils.find_base_dir(), 'services'))


def find_service_files(service_name):
    service_dir = get_services_directory()
    LOG.debug('Looking for services files in %s', service_dir)

    if not os.path.exists(service_dir):
        raise exception.KollaNotFoundException(service_dir,
                                               entity='service directory')

    bootstrap_dir = os.path.join(service_dir, '../bootstrap/')
    LOG.debug('Looking for bootstrap files in %s', service_dir)
    if not os.path.exists(bootstrap_dir):
        raise exception.KollaNotFoundException(bootstrap_dir,
                                               entity='bootstrap directory')

    short_name = service_name.split('/')[-1]
    files = []
    for root, dirs, names in os.walk(service_dir):
        for name in names:
            if short_name in name:
                files.append(os.path.join(root, name))

    for root, dirs, names in os.walk(bootstrap_dir):
        for name in names:
            if short_name in name:
                files.append(os.path.join(root, name))

    if not files:
        raise exception.KollaNotFoundException(service_dir,
                                               entity='service definition')
    return files
