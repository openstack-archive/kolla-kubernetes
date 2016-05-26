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

import datetime
import os.path
import subprocess
import tempfile
import time

from oslo_config import cfg
from oslo_log import log as logging
import yaml

from kolla_kubernetes.common import file_utils
from kolla_kubernetes.common import jinja_utils
from kolla_kubernetes.common import utils
from kolla_kubernetes import service_definition

LOG = logging.getLogger()
CONF = cfg.CONF
CONF.import_group('kolla', 'kolla_kubernetes.config')
CONF.import_group('kolla_kubernetes', 'kolla_kubernetes.config')

PROJECT_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '../..'))


def _create_working_directory():
    ts = time.time()
    ts = datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d_%H-%M-%S_')
    temp_dir = tempfile.mkdtemp(prefix='kolla-' + ts)
    working_dir = os.path.join(temp_dir, 'kubernetes')
    os.makedirs(working_dir)
    return working_dir


def _load_variables_from_file(project_name):
    jvars = utils.JvarsDict()
    f = file_utils.find_config_file('kolla-kubernetes.yml')
    if os.path.exists(f):
        with open(f, 'r') as gf:
            jvars.set_global_vars(yaml.load(gf))
    else:
        LOG.warning('Unable to load %s', f)
    f = file_utils.find_config_file('globals.yml')
    if os.path.exists(f):
        with open(f, 'r') as gf:
            jvars.set_global_vars(yaml.load(gf))
    else:
        LOG.warning('Unable to load %s', f)
    f = file_utils.find_config_file('passwords.yml')
    if os.path.exists(f):
        with open(f, 'r') as gf:
            jvars.update(yaml.load(gf))
    else:
        LOG.warning('Unable to load %s', f)
    # Apply the basic variables that aren't defined in any config file.
    jvars.update({
        'deployment_id': CONF.kolla.deployment_id,
        'node_config_directory': '',
        'timestamp': str(time.time())
    })

    dir = file_utils.get_shared_directory()
    all_yml = os.path.join(dir, 'ansible/group_vars/all.yml')
    local_dir = os.path.join(PROJECT_ROOT, 'kolla/ansible/')

    if dir and os.path.exists(all_yml):
        jinja_utils.yaml_jinja_render(all_yml, jvars)
    elif dir and os.path.exists(local_dir):
        local_group_vars = os.path.join(local_dir, 'group_vars/all.yml')
        jinja_utils.yaml_jinja_render(local_group_vars, jvars)
    else:
        LOG.warning('Unable to load %s', all_yml)

    proj_ansible_roles = os.path.join(dir, 'ansible/roles', project_name,
                                      'defaults', 'main.yml')
    local_ansible_roles = os.path.join(local_dir, 'roles', project_name,
                                       'defaults', 'main.yml')

    if dir and os.path.exists(proj_ansible_roles):
        jinja_utils.yaml_jinja_render(proj_ansible_roles, jvars)
    elif dir and os.path.exists(local_ansible_roles):
        jinja_utils.yaml_jinja_render(local_ansible_roles, jvars)
    else:
        LOG.warning('Unable to load %s', proj_ansible_roles)

    common_ansible_roles = os.path.join(dir, 'ansible/roles', 'common',
                                        'defaults', 'main.yml')
    common_local_ansible_roles = os.path.join(local_dir, 'roles', 'common',
                                              'defaults', 'main.yml')

    if dir and os.path.exists(common_ansible_roles):
        jinja_utils.yaml_jinja_render(common_ansible_roles, jvars)
    elif dir and os.path.exists(common_local_ansible_roles):
        jinja_utils.yaml_jinja_render(common_local_ansible_roles, jvars)
    else:
        LOG.warning('Unable to load %s', common_ansible_roles)
    return jvars


def _build_runner(working_dir, service_name, pod_list, variables=None):
    for filename in service_definition.find_service_files(service_name):
        proj_filename = filename.split('/')[-1].replace('.j2', '')
        proj_name = filename.split('/')[-2]
        LOG.debug(
            'proj_filename : %s proj_name: %s' % (proj_filename, proj_name))

        variables = _load_variables_from_file(proj_name)

        content = yaml.load(
            jinja_utils.jinja_render(filename, variables))
        with open(os.path.join(working_dir, proj_filename), 'w') as f:
            LOG.debug('_build_runner : service file : %s' %
                      os.path.join(working_dir, proj_filename))
            f.write(yaml.dump(content, default_flow_style=False))


def run_service(service_name, variables=None):
    working_dir = _create_working_directory()
    pod_list = service_definition.get_pod_definition(service_name)
    _build_runner(working_dir, service_name, pod_list, variables=variables)
    _deploy_instance(working_dir, service_name, pod_list)


def kill_service(service_name, variables=None):
    working_dir = _create_working_directory()
    pod_list = service_definition.get_pod_definition(service_name)
    _build_runner(working_dir, service_name, pod_list, variables=variables)
    _delete_instance(working_dir, service_name, pod_list)


def _deploy_instance(directory, service_name, pod_list):
    server = "--server=" + CONF.kolla_kubernetes.host

    for pod in pod_list:
        container_list = service_definition.get_container_definition(pod)
        for container in container_list:
            cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create",
                   "configmap", '%s-configmap' % container]
            cmd = cmd + ['--from-file=%s' % f
                         for f in
                         file_utils.get_service_config_files(container)]

            LOG.info('Command : %r' % cmd)
            subprocess.call(cmd)

    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create", "-f",
           directory]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)


def _delete_instance(directory, service_name, pod_list):
    server = "--server=" + CONF.kolla_kubernetes.host

    for pod in pod_list:
        container_list = service_definition.get_container_definition(pod)
        for container in container_list:
            cmd = [CONF.kolla_kubernetes.kubectl_path, server, "delete",
                   "configmap", '%s-configmap' % container]

            LOG.info('Command : %r' % cmd)
            subprocess.call(cmd)

    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "delete", "-f",
           directory]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)
