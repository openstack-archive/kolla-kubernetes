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

import json
import os
import yaml

from kolla_kubernetes.tests import base
from kolla_kubernetes.utils import ExecUtils


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


class TestK8sTemplatesTest(base.BaseTestCase):

    def test_validate_templates(self):
        srcdir = os.environ['HELMDIR']
        helmbin = os.environ['HELMBIN']
        repodir = os.environ['REPODIR']
        microdir = os.path.join(srcdir, "microservice")
        microservices = os.listdir(microdir)
        packages = [p for p in microservices if _isdir(microdir, p)]
        for package in packages:
            with open(os.path.join(microdir, package, 'Chart.yaml',
                      'r')) as stream:
                version = yaml.load(stream)['Version']

            cmd = "%s template %s/%s-%s.tgz" % (helmbin, repodir,
                                                package, version)
            out, err = ExecUtils.exec_command(cmd)
            if err:
                raise err

            y = yaml.load(out)
            js = '[]'
            try:
                # If there is a beta init container, validate it is proper
                # json
                key = 'pod.beta.kubernetes.io/init-containers'
                js = y['spec']['template']['metadata']['annotations'][key]
            except KeyError:
                pass
            except TypeError as e:
                m = ("'NoneType' object has no attribute '__getitem__'",
                     "'NoneType' object is not subscriptable")
                if e.args[0] not in m:
                    raise
            json.loads(js)
