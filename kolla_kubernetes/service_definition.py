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


def get_services_directory():
    return (CONF.service_dir or
            os.path.join(file_utils.find_base_dir(), 'services'))

def get_bootstrap_directory():
    return (CONF.bootstrap_dir or
            os.path.join(file_utils.find_base_dir(), 'bootstrap'))

def find_service_files(service_name, task):

    if task == 'service':
        working_dir = get_services_directory()
        LOG.debug('Looking for services files in %s', working_dir)
    elif task == 'boostrap':
        working_dir = get_boostrap_directory()
        LOG.debug('Looking for bootstrap files in %s', working_dir)

    if not os.path.exists(working_dir) and task  == 'service':
        raise exception.KollaNotFoundException(working_dir,
                                               entity='service directory')
    elif not os.path.exists(working_dir) and task == 'bootstrap':
        raise exception.KollaNotFoundException(working_dir,
                                               entity='bootstrap directory')

    short_name = service_name.split('/')[-1]

    files = []
    for root, dirs, names in os.walk(working_dir):
        for name in names:
            if short_name in name:
                files.append(os.path.join(root, name))

    if not files and task == 'service':
        raise exception.KollaNotFoundException(working_dir,
                                               entity='service definition')
    elif not files and task == 'bootstrap':
        raise exception.KollaNotFoundException(working_dir,
                                               entity='bootstrap definition')
    return files
