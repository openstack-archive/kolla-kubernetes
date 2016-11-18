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

import argparse
import sys
import yaml

from kubernetes_operator import Operator
from mariadb_operator.mariadb_operator import MariadbOperator


def parser():
    parser = argparse.ArgumentParser(description='Operator Client.')

    parser.add_argument("operator",
                        help='Input which operator to spawn')
    return parser.parse_args()


def main():
    args = parser()
    service = args.operator

    # WIP File for testing.
    with open("../etc/kolla-kubernetes/%s/operator.yaml" % service,
              'r') as info:
        try:
            user_data = yaml.load(info)
        except yaml.YAMLError as exc:
            if hasattr(exc, 'problem_mark'):
                mark = exc.problem_mark
                print("Yaml Error line %s: column %s" % (mark.line + 1,
                                                         mark.column + 1))

    operator_dict = {'mariadb': MariadbOperator(user_data)}

    if user_data.get('type') == 'Operator':
        op = Operator(user_data)
        op.deploy()

    if user_data.get('type') == 'ServiceOperator':
        service_op = operator_dict.get(service)
        service_op.deploy()

if __name__ == '__main__':
    sys.exit(main())
