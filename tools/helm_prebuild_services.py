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

import os
import subprocess
import sys


def helm_dep_up(srcdir):
    command_line = "cd %s; helm dep up" % (srcdir)
    try:
        res = subprocess.check_output(
            command_line, shell=True,
            executable='/bin/bash')
        res = res.strip()  # strip whitespace
        if res != "":
            print(res)
    except subprocess.CalledProcessError as e:
        print(e)
        raise


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


def main():
    path = os.path.abspath(os.path.dirname(sys.argv[0]))

    srcdir = os.path.join(path, "..", "helm")
    svcdir = os.path.join(srcdir, "service")
    services = os.listdir(svcdir)

    for package in [p for p in services if _isdir(svcdir, p)]:
        helm_dep_up(os.path.join(os.path.join(svcdir, package)))


if __name__ == '__main__':
    sys.exit(main())
