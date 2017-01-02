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


def helm_build_package(repodir, srcdir):
    command_line = "cd %s; helm package %s" % (repodir, srcdir)
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
    srcdir = os.path.join(path, "../helm")
    if len(sys.argv) < 2:
        sys.stderr.write("You must specify the repo directory to build in.\n")
        sys.exit(-1)
    repodir = sys.argv[1]
    if not os.path.isdir(repodir):
        sys.stderr.write("The specified repo directory does not exist.\n")
        sys.exit(-1)

    microdir = os.path.join(srcdir, "microservice")
    microservices = os.listdir(microdir)

    packages = [p for p in microservices if _isdir(microdir, p)]
    count = 1
    for package in packages:
        if sys.stdout.isatty():
            sys.stdout.write("\rProcessing %i/%i" % (count, len(packages)))
            sys.stdout.flush()
            count += 1
        helm_build_package(repodir, os.path.join(microdir, package))
    if sys.stdout.isatty():
            sys.stdout.write("\r                             \n")
            sys.stdout.flush()

if __name__ == '__main__':
    sys.exit(main())
