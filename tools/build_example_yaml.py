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

import errno
import os
import sys
import yaml


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


def merge_dict(a, b):
    for key in b:
        if key not in a:
            a[key] = b[key]
        else:
            if isinstance(b[key], dict):
                merge_dict(a[key], b[key])
            else:
                a[key] = b[key]


def main():
    path = os.path.abspath(os.path.dirname(sys.argv[0]))

    exampledir = os.path.join(path, "..", "examples")
    try:
        os.makedirs(exampledir)
    except OSError as e:
        if e.errno != errno.EEXIST:
            raise

    srcdir = os.path.join(path, "..", "helm")
    microdir = os.path.join(srcdir, "microservice")
    microservices = os.listdir(microdir)
    values = {}

    for package in [p for p in microservices if _isdir(microdir, p)]:
        values_file = os.path.join(microdir, package, "values.yaml")
        with open(values_file, "r") as f:
            package_values = yaml.safe_load(f)
            merge_dict(values, package_values)

    # Remove some package specific values:
    if 'type' in values:
        del values['type']
    if 'element_name' in values['global']:
        del values['global']['element_name']

    y = yaml.safe_dump(values, default_flow_style=False)
    with open(os.path.join(exampledir, "cloud.yaml"), "w") as f:
        f.write("\n".join(["#%s" % l for l in y.split("\n")]))


if __name__ == '__main__':
    sys.exit(main())
