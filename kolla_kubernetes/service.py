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

from kolla_kubernetes.common.pathfinder import PathFinder
from kolla_kubernetes.common.utils import FileUtils
from kolla_kubernetes.common.utils import JinjaUtils
from kolla_kubernetes import service_definition

LOG = logging.getLogger()
CONF = cfg.CONF
CONF.import_group('kolla', 'kolla_kubernetes.config')
CONF.import_group('kolla_kubernetes', 'kolla_kubernetes.config')


def _create_working_directory(target='services'):
    ts = time.time()
    ts = datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d_%H-%M-%S_')
    temp_dir = tempfile.mkdtemp(prefix='kolla-' + ts)
    working_dir = os.path.join(temp_dir, 'kubernetes')
    working_dir = os.path.join(working_dir, target)
    os.makedirs(working_dir)
    return working_dir


def _load_variables_from_file(service_name=None, debug_regex=None):
    # Apply basic variables that aren't defined in any config file
    jvars = {'deployment_id': CONF.kolla.deployment_id,
             'node_config_directory': '',
             'timestamp': str(time.time())}

    # Create the prioritized list of config files that need to be
    # merged.  Search method for config files: locks onto the first
    # path where the file exists.  Search method for template files:
    # locks onto the first path that exists, and then expects the file
    # to be there.
    kolla_dir = PathFinder.find_kolla_dir()
    files = [
        PathFinder.find_config_file('kolla-kubernetes.yml'),
        PathFinder.find_config_file('globals.yml'),
        PathFinder.find_config_file('passwords.yml'),
        os.path.join(kolla_dir, 'ansible/group_vars/all.yml')]
    if service_name is not None:
        files.append(os.path.join(kolla_dir, 'ansible/roles',
                                  service_name, 'defaults/main.yml'))
    files.append(os.path.join(kolla_dir,
                              'ansible/roles/common/defaults/main.yml'))

    # Create the config dict
    x = JinjaUtils.merge_configs_to_dict(reversed(files), jvars, debug_regex)

    # Render values containing nested jinja variables
    return JinjaUtils.dict_self_render(x)


def _build_bootstrap(working_dir, service_name, variables=None):
    for filename in service_definition.find_bootstrap_files(service_name):
        proj_filename = filename.split('/')[-1].replace('.j2', '')
        proj_name = filename.split('/')[-2]
        LOG.debug(
            'proj_filename : %s proj_name: %s' % (proj_filename, proj_name))

        variables = _load_variables_from_file(proj_name)
        content = JinjaUtils.render_jinja(
            variables,
            FileUtils.read_string_from_file(filename))

        filename = os.path.join(working_dir, proj_filename)
        LOG.debug('_build_bootstrap : file : %s' % filename)
        FileUtils.write_string_to_file(content, filename)


def _build_runner(working_dir, service_name, pod_list, variables=None):
    for filename in service_definition.find_service_files(service_name):
        proj_filename = filename.split('/')[-1].replace('.j2', '')
        proj_name = filename.split('/')[-2]
        LOG.debug(
            'proj_filename : %s proj_name: %s' % (proj_filename, proj_name))

        variables = _load_variables_from_file(proj_name)
        content = JinjaUtils.render_jinja(
            variables,
            FileUtils.read_string_from_file(filename))

        filename = os.path.join(working_dir, proj_filename)
        LOG.debug('_build_runner : service file : %s' % filename)
        FileUtils.write_string_to_file(content, filename)


def execute_action(service_name, action):
    service_list = None
    if service_name == 'all':
        service_list = service_definition.get_service_dict()
    else:
        service_list = [service_name]

    for service in service_list:
        if action == 'bootstrap':
            bootstrap_service(service)
        elif action == 'run':
            run_service(service)
        elif action == 'kill':
            kill_service(service)


def bootstrap_service(service_name, variables=None):
    working_dir = _create_working_directory('bootstrap')
    _build_bootstrap(working_dir, service_name, variables=variables)
    _bootstrap_instance(working_dir, service_name)


def run_service(service_name, variables=None):
    working_dir = _create_working_directory()
    pod_list = service_definition.get_pod_definition(service_name)
    _build_runner(working_dir, service_name, pod_list, variables=variables)
    _deploy_instance(working_dir, service_name, pod_list)


def kill_service(service_name, variables=None):
    working_dir = _create_working_directory()
    pod_list = service_definition.get_pod_definition(service_name)
    _build_runner(working_dir, service_name, pod_list, variables=variables)
    _build_bootstrap(working_dir, service_name, variables=variables)
    _delete_instance(working_dir, service_name, pod_list)


def _bootstrap_instance(directory, service_name):
    server = "--server=" + CONF.kolla_kubernetes.host
    pod_list = service_definition.get_pod_definition(service_name)
    for pod in pod_list:
        container_list = service_definition.get_container_definition(pod)
        for container in container_list:
            cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create",
                   "configmap", '%s-configmap' % container]
            for f in PathFinder.find_kolla_service_config_files(container):
                cmd = cmd + ['--from-file=%s=%s' % (
                    os.path.basename(f).replace("_", "-"), f)]

            # TODO(rhallisey): improve error handling to check if configmap
            # already exists
            LOG.info('Command : %r' % cmd)
            subprocess.call(cmd)

    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create", "-f",
           directory]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)


def _deploy_instance(directory, service_name, pod_list):
    server = "--server=" + CONF.kolla_kubernetes.host
    pod_list = service_definition.get_pod_definition(service_name)
    for pod in pod_list:
        container_list = service_definition.get_container_definition(pod)
        for container in container_list:
            cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create",
                   "configmap", '%s-configmap' % container]
            for f in PathFinder.find_kolla_service_config_files(container):
                cmd = cmd + ['--from-file=%s=%s' % (
                    os.path.basename(f).replace("_", "-"), f)]

            # TODO(rhallisey): improve error handling to check if configmap
            # already exists
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
