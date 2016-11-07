#!/usr/bin/env python

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
import re
import subprocess
import yaml

logging.basicConfig()
LOG = logging.getLogger(__name__)


def main():
    check_k8s_version()
    check_k8s_namespace()


def check_k8s_namespace():
    LOG.warning('Checking preferred kubernetes namespace')
    try:
        current_context = subprocess.check_output(
            "kubectl config current-context", shell=True).strip()
        res = subprocess.check_output("kubectl config view", shell=True)
        config = yaml.load(res)

        for context in config["contexts"]:
            if context["name"] == current_context:
                if ("namespace" not in context["context"] or
                        context["context"]["namespace"] != "kolla"):
                    LOG.error("Preferred namespace is not set to 'kolla'.")

    except subprocess.CalledProcessError as e:
        print(e)
    except yaml.YAMLError as exc:
        print(exc)


def check_k8s_version():
    LOG.warning('Checking kubernetes version')
    versions = []
    try:
        res = subprocess.check_output("kubectl version", shell=True).strip()
        versions = res.split('\n')

        for version in versions:
            major_version = int(re.search('Major:"(.*?)\"', version).group(1))
            minor_version = int(re.search('Minor:"(.*?)\"', version).group(1))
            if (major_version < 1 or
                    (major_version <= 1 and minor_version < 3)):
                LOG.error("Minimum supported version of kubernetes is 1.3.0")
    except subprocess.CalledProcessError as e:
        print(e)

if __name__ == '__main__':
    main()
