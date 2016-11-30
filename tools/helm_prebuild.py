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

import copy
import os
import shutil
import sys
import yaml


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


def main():
    path = os.path.abspath(os.path.dirname(sys.argv[0]))

    srcdir = os.path.join(path, "..", "helm")
    microdir = os.path.join(srcdir, "microservice")
    microservices = os.listdir(microdir)
    values = yaml.load(open(os.path.join(srcdir, "all_values.yaml")))

    for package in [p for p in microservices if _isdir(microdir, p)]:
        template = os.path.join("templates", "_common_lib.yaml")
        shutil.copy(os.path.join(srcdir, "kolla-common", template),
                    os.path.join(microdir, package, template))
        pkg_values = copy.deepcopy(values['common'])
        try:
            pkg_values.update(values[package])
        except KeyError:
            pass
        f = open(os.path.join(microdir, package, "values.yaml"), "w")
        f.write("# This file is generated. Please edit all_values.yaml\n")
        f.write("# and rerun tools/helm_prebuild.py\n")
        f.write(yaml.safe_dump(pkg_values, default_flow_style=False))
        f.close()

if __name__ == '__main__':
    sys.exit(main())
