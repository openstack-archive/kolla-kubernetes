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

def run_service(service_name, service_dir, variables=None):
    # generate zk variables
    if service_name == 'nova-compute':
        service_list = ['nova-compute', 'nova-libvirt', 'openvswitch-vswitchd',
                        'neutron-openvswitch-agent', 'openvswitch-db']
    elif service_name == 'network-node':
        service_list = ['neutron-openvswitch-agent', 'neutron-dhcp-agent',
                        'neutron-metadata-agent', 'openvswitch-vswitchd',
                        'openvswitch-db neutron-l3-agent']
    #TODO: load this service _list from config
    elif service_name == 'all':
        service_list = ['keystone-init', 'keystone-api', 'keystone-db-sync',
                        'glance-init', 'mariadb', 'rabbitmq', 'glance-registry',
                        'glance-api', 'nova-init', 'nova-api', 'nova-scheduler',
                        'nova-conductor', 'nova-consoleauth', 'neutron-init',
                        'neutron-server', 'horizon', 'nova-compute',
                        'nova-libvirt', 'openvswitch-vswitchd',
                        'neutron-openvswitch-agent', 'openvswitch-db',
                        'neutron-dhcp-agent', 'neutron-metadata-agent',
                        'openvswitch-db neutron-l3-agent']
    elif service_name == 'zookeeper':
        service_list = []
    else:
        service_list = [service_name]
    # for service in service_list:
    #     _build_runner(service, service_dir, variables=variables)
    # _deploy_instance(service_name)


def kill_service(service_name):
    # if service_name == "all":
    #     with zk_utils.connection() as zk:
    #         status_node = os.path.join('kolla', CONF.kolla.deployment_id,
    #                                    'status')
    #         zk.delete(status_node, recursive=True)
    # _delete_instance(service_name)
    pass


