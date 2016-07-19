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

import logging
import os
import sys

from kolla_kubernetes import exception
from oslo_config import cfg

CONF = cfg.CONF
LOG = logging.getLogger(__name__)


class PathFinder(object):

    _find_cache = {}

    @staticmethod
    def find_installed_root():
        # Full installs use this root path to locate ./share/kolla
        # For system, resolves to /usr/local
        # For virtualenv, resolves to /path/to/venv
        return os.path.abspath(os.path.join(os.path.dirname(
            os.path.realpath(sys.argv[0])), '../'))

    @staticmethod
    def find_development_root():
        # Editable installs (aka. Development: pip install --editable .)
        #   use this root path to locate ../kolla
        # For editable, resolves to /path/to/git/repo/kolla-kubernetes
        return os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))

    @staticmethod
    def find_kolla_dir():
        return PathFinder._find(KOLLA_SEARCH_PATHS, None)

    @staticmethod
    def find_kolla_kubernetes_dir():
        return PathFinder._find(KOLLA_KUBERNETES_SEARCH_PATHS, None)

    @staticmethod
    def find_config_file(filename):
        search_paths = CONFIG_SEARCH_PATHS
        for d in search_paths:
            f = os.path.join(d, filename)
            if os.path.isfile(f):
                return f
        raise exception.KollaFileNotFoundException(
            "Unable to locate file=[{}] in search_paths=[{}]".format(
                filename, ", ".join(search_paths))
        )

    @staticmethod
    def find_config_files(service_name):
        path = PathFinder.find_config_dir(service_name)
        return PathFinder._list_dir_files(path)

    @staticmethod
    def find_config_dir(service_name):
        return PathFinder._find(CONFIG_SEARCH_PATHS, service_name)

    @staticmethod
    def _find(search_paths, dir_or_file):
        # check the cache first
        cache_key = ("-".join(search_paths) + ":" +
                     (dir_or_file if dir_or_file is not None else ""))
        if cache_key in PathFinder._find_cache:
            return PathFinder._find_cache[cache_key]

        # returns the first directory that exists
        for path in search_paths:
            p = path
            if dir_or_file is not None:
                p = os.path.join(path, dir_or_file)
            if os.path.exists(p):
                PathFinder._find_cache[cache_key] = p
                return p
        raise exception.KollaDirNotFoundException(
            "Unable to locate {} directory in search_paths=[{}]".format(
                dir_or_file, ", ".join(search_paths))
        )

    @staticmethod
    def _list_dir_files(path):
        paths = [os.path.join(path, fn) for fn in next(os.walk(path))[2]]
        return paths


# prioritize directories to search for /etc files
CONFIG_SEARCH_PATHS = [
    # Search installation paths first
    '/etc/kolla',
    '/etc/kolla-kubernetes',
    # Then development paths
    os.path.abspath(os.path.join(PathFinder.find_development_root(),
                                 '../kolla/etc/kolla')),
    os.path.abspath(os.path.join(PathFinder.find_development_root(),
                                 './etc/kolla-kubernetes')),
]

# prioritize directories to search for kolla sources
KOLLA_SEARCH_PATHS = [
    # Search installation paths first
    os.path.abspath(os.path.join(PathFinder.find_installed_root(),
                                 './share/kolla')),
    '/usr/share/kolla',
    # Then search development paths
    os.path.abspath(os.path.join(PathFinder.find_development_root(),
                                 '../kolla')),
    os.path.abspath(os.path.join(PathFinder.find_development_root(),
                                 'kolla')),
]

# prioritize directories to search for kolla-kubernetes sources
KOLLA_KUBERNETES_SEARCH_PATHS = [
    # Search installation paths first
    os.path.abspath(os.path.join(PathFinder.find_installed_root(),
                                 './share/kolla-kubernetes')),
    '/usr/share/kolla-kubernetes',
    # Then search development paths
    os.path.abspath(os.path.join(PathFinder.find_development_root())),
]
