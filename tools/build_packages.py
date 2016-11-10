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
import shutil
import subprocess
import sys
import tempfile


def helm_build_package(repodir, srcdir):
    command_line = "cd %s; helm package %s" % (repodir, srcdir)
    try:
        res = subprocess.check_output(
            command_line, shell=True,
            executable='/bin/bash')
        res = res.strip()  # strip whitespace
        print(res)
    except subprocess.CalledProcessError as e:
        print(e)
        raise


def trivial_template(src, dest, package, subpackage):
    f = open(src, 'r')
    lines = f.read()
    f.close()
    f = open(dest, 'w')
    lines = lines.replace('@NAME@', "%s-%s" % (package['name'],
                                               subpackage['name']))
    f.write(lines)
    f.close()


def build_packages(srcdir, repodir, tmpdir):
    helm_build_package(repodir, os.path.join(srcdir, "openstack-kolla-common"))

    packages = [{
        'name': 'neutron',
        'subpackages': [{
            'name': 'l3-agent',
            'type': 'daemonset'
        }, {
            'name': 'openvswitch-agent',
            'type': 'daemonset'
        }]
    }]

    for package in packages:
        svcpackagedir = os.path.join(tmpdir, package['name'])
        shutil.copytree(os.path.join(srcdir, package['name']),
                        svcpackagedir)
        os.mkdir(os.path.join(svcpackagedir, "charts"))

        for subpackage in package['subpackages']:
            packagedir = os.path.join(tmpdir, "%s-%s" % (package['name'],
                                                         subpackage['name']))
            os.mkdir(packagedir)
            packagetemplatedir = os.path.join(packagedir, "templates")
            os.mkdir(packagetemplatedir)
            os.mkdir(os.path.join(packagedir, "charts"))

            # FIXME unhardcode this
            shutil.copy(os.path.join(repodir,
                                     'openstack-kolla-common-2.0.2-1.tgz'),
                        os.path.join(packagedir, 'charts',
                                     'openstack-kolla-common-2.0.2-1.tgz'))

            template = "%s_%s.yaml" % (subpackage['name'].replace('-', '_'),
                                       subpackage['type'])

            trivial_template(os.path.join(srcdir, 'src', 'common_main.yaml'),
                             os.path.join(packagetemplatedir, template),
                             package, subpackage)

            shutil.copy(os.path.join(srcdir, 'src', package['name'],
                                     'templates', template),
                        os.path.join(packagetemplatedir, "_main.yaml"))
            shutil.copy(os.path.join(srcdir, 'src', package['name'],
                                     'values', template),
                        os.path.join(packagedir, 'values.yaml'))

            f = open(os.path.join(srcdir, 'src', 'common_values.yaml'), 'r')
            lines = f.read()
            f.close()
            f = open(os.path.join(packagedir, 'values.yaml'), 'a')
            f.write(lines)
            f.close()

            trivial_template(os.path.join(srcdir, 'src', 'common_chart.yaml'),
                             os.path.join(packagedir, 'Chart.yaml'),
                             package, subpackage)
            helm_build_package(repodir, packagedir)

            # FIXME unhardcode version...
            tgz = "%s-%s-2.0.2-1.tgz" % (package['name'], subpackage['name'])
            shutil.copy(os.path.join(repodir, tgz),
                        os.path.join(svcpackagedir, 'charts'))

        helm_build_package(repodir, svcpackagedir)


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
    tmpdir = tempfile.mkdtemp()
    try:
        build_packages(srcdir, repodir, tmpdir)
    except Exception:
        shutil.rmtree(tmpdir)
        raise
    shutil.rmtree(tmpdir)

if __name__ == '__main__':
    sys.exit(main())
