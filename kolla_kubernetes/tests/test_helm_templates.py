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

    def _validate_image_pull_policy(self, package, pod):
        for container in pod['spec']['containers']:
            if 'imagePullPolicy' not in container:
                raise Exception("imagePullPolicy not in %s" % package)

    def test_validate_templates(self):
        srcdir = os.environ['HELMDIR']
        helmbin = os.environ['HELMBIN']
        repodir = os.environ['REPODIR']
        microdir = os.path.join(srcdir, "microservice")
        microservices = os.listdir(microdir)
        packages = [p for p in microservices if _isdir(microdir, p)]
        print("Working on:")
        for package in packages:
            print("    %s" % package)
            with open(os.path.join(microdir, package, 'Chart.yaml')) as stream:
                version = yaml.safe_load(stream)['version']

            cmd = "%s template %s/%s-%s.tgz" % (helmbin, repodir,
                                                package, version)
            out, err = ExecUtils.exec_command(cmd)
            if err:
                raise err

            #FIXME
            if package == 'iscsi-target-daemonset' or package == "iscsid-daemonset":
              print(out.readlines())
              raise ("ERROR2")

            l = yaml.safe_load_all(out)
            for y in l:
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
                pod = None
                try:
                    pod = y['spec']['template']
                except Exception:
                    pass
                if pod:
                    self._validate_image_pull_policy(package, pod)
