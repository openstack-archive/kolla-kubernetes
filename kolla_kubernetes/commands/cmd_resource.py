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

from __future__ import print_function
import json
import os
import re
import subprocess
import sys
import tempfile
import yaml

from kolla_kubernetes.commands import base_command
from kolla_kubernetes import pathfinder
from kolla_kubernetes import service_resources
from kolla_kubernetes import utils

KKR = service_resources.KollaKubernetesResources.Get()


class ResourceBase(base_command.KollaKubernetesBaseCommand):
    """Create, delete, or query status for kolla-kubernetes resources"""

    def get_parser(self, prog_name):
        parser = super(ResourceBase, self).get_parser(prog_name)
        parser.add_argument(
            "action",
            metavar="<action>",
            help=("One of [%s]" % ("|".join(service_resources.Service.
                                            VALID_ACTIONS)))
        )
        parser.add_argument(
            "resource_type",
            metavar="<resource-type>",
            help=("One of [%s]" % ("|".join(service_resources.Service.
                                            VALID_RESOURCE_TYPES)))
        )
        return parser

    def validate_args(self, args):
        if args.action not in service_resources.Service.VALID_ACTIONS:
            msg = ("action [{}] not in valid actions [{}]".format(
                args.action,
                "|".join(service_resources.Service.VALID_ACTIONS)))
            raise Exception(msg)
        if args.resource_type not in service_resources.Service.\
                VALID_RESOURCE_TYPES:
            msg = ("resource_type [{}] not in valid resource_types [{}]"
                   .format(args.resource_type,
                           "|".join(service_resources.Service.
                                    VALID_RESOURCE_TYPES)))
            raise Exception(msg)


class ResourceTemplate(ResourceBase):
    """Jinja process kolla-kubernetes resource template files"""

    # This command adds the CLI params as part of the Jinja vars for processing
    # templates. This is needed because some of the templates will need to know
    # the arguments with which this CLI is called.  For example, some
    # resource-type "disk" templates may reference '{{
    # kolla_kubernetes.cli.args.action }}' to produce output such as "gcloud
    # disk create" or "gcloud disk delete" based on the CLI params.  Most
    # templates will not require this, but it is needed for some.

    def get_parser(self, prog_name):
        parser = super(ResourceTemplate, self).get_parser(prog_name)
        parser.add_argument(
            "resource_name",
            metavar="<resource-name>",
            help=("The unique resource-name under service->resource_type")
        )
        parser.add_argument(
            '--print-jinja-vars',
            action='store_true',
            help=("If this boolean is set, the final jinja vars dict used as"
                  " input for template processing will be printed to stderr.  "
                  " The vars dict is created by merging configuration files "
                  " from several sources before applying the dict to itself.")
        ),
        parser.add_argument(
            '--print-jinja-keys-regex',
            metavar='<print-jinja-keys-regex>',
            type=str,
            default=None,
            help=("If this regex string is set, all matching keys encountered"
                  " during the creation of the jinja vars dict will be printed"
                  " to stderr at each stage of processing.  The vars dict is"
                  " created by merging configuration files from several"
                  " sources before applying the dict to itself.")
        )
        return parser

    def take_action(self, args, skip_and_return=False):
        # Validate input arguments
        self.validate_args(args)
        service_name = KKR.getServiceNameByResourceTypeName(args.resource_type,
                                                            args.resource_name)
        service = KKR.getServiceByName(service_name)
        rt = service.getResourceTemplateByTypeAndName(
            args.resource_type, args.resource_name)

        variables = KKR.GetJinjaDict(service_name, vars(args),
                                     args.print_jinja_keys_regex)

        # Merge the template vars with the jinja vars before processing
        variables['kolla_kubernetes'].update(
            {"template": {"vars": rt.getVars()}})

        # handle the debug option --print-jinja-vars
        if args.print_jinja_vars is True:
            print(utils.YamlUtils.yaml_dict_to_string(variables),
                  file=sys.stderr)

        res = ""
        if args.resource_type == 'configmap' and rt.getTemplate() == 'auto':
            nsname = 'kolla_kubernetes_namespace'
            cmd = "kubectl create configmap {} -o yaml --dry-run"
            cmd = cmd.format(args.resource_name)

            # FIXME strip configmap out of name until its removed perminantly
            short_name = re.sub('-configmap$', '', args.resource_name)
            for f in pathfinder.PathFinder.find_config_files(short_name):
                cmd += ' --from-file={}={}'.format(
                    os.path.basename(f).replace("_", "-"), f)

            # Execute the command
            out, err = utils.ExecUtils.exec_command(cmd)
            y = yaml.load(out)
            y['metadata']['namespace'] = variables[nsname]

            res = yaml.safe_dump(y)
        else:
            # process the template
            res = utils.JinjaUtils.render_jinja(
                variables,
                utils.FileUtils.read_string_from_file(rt.getTemplatePath()))

        if skip_and_return:
            return res

        print(res)


class Resource(ResourceTemplate):
    """Create kolla-kubernetes resources"""

    def validate_args(self, args):
        super(Resource, self).validate_args(args)
        if args.action not in ['create', 'delete', 'status']:
            msg = ("action [{}] currently not supported".format(
                args.action))
            raise Exception(msg)

    def take_action(self, args):
        t = super(Resource, self).take_action(args, skip_and_return=True)
        y = yaml.load(t)
        kind = y['kind']
        kind_map = {
            'PetSet': 'petset',
            'Pod': 'pod',
            'ReplicationController': 'rc',
            'DaemonSet': 'daemonset',
            'Job': 'job',
            'Deployment': 'deployment',
            'ConfigMap': 'configmap',
            'Service': 'svc',
            'PersistentVolume': 'pv',
            'PersistentVolumeClaim': 'pvc',
        }
        if kind not in kind_map:
            msg = ("unknown template kind [{}].".format(kind))
            raise Exception(msg)
        nsflag = ""
        if kind != 'PersistentVolume':
            nsflag = " --namespace={}".format(
                y['metadata']['namespace']
            )
        if args.action == 'create':
            with tempfile.NamedTemporaryFile() as tf:
                tf.write(t)
                tf.flush()
                s = "kubectl {} -f {}{}".format(
                    args.action, tf.name, nsflag)
                subprocess.call(s, shell=True)
                tf.close()
        elif args.action == "delete":
            s = "kubectl delete {} {}{}".format(
                kind_map[kind], y['metadata']['name'],
                nsflag)
            subprocess.call(s, shell=True)
        elif args.action == 'status':
            s = "kubectl get {} {}{}".format(
                kind_map[kind], y['metadata']['name'],
                nsflag)
            subprocess.call(s, shell=True)


class ResourceMap(base_command.KollaKubernetesBaseCommand):
    """List available kolla-kubernetes resources to be created or deleted"""

    # If the operator has any question on what Services have what resources,
    # and what resources reference which resourcefiles (on disk), then this
    # command is helpful.  This command prints the available resources in a
    # tree of Service->ResourceType->ResourceFiles.

    def get_parser(self, prog_name):
        parser = super(ResourceMap, self).get_parser(prog_name)
        parser.add_argument(
            "--resource-type",
            metavar="<resource-type>",
            help=("Filter by one of [%s]" % (
                "|".join(service_resources.Service.VALID_RESOURCE_TYPES)))
        )
        parser.add_argument(
            "--service-name",
            metavar="<service-name>",
            help=("Filter by one of [%s]" % (
                "|".join(KKR.getServices().keys())))
        )
        parser.add_argument(
            "-o",
            "--output",
            metavar="output",
            default="text",
            help=("Format output into one of [%s]" % (
                "|".join(['txt', 'json', 'yaml'])))
        )
        return parser

    def take_action(self, args):
        resources = []
        for service_name, s in KKR.getServices().items():

            # Skip specific services if the user has defined a filter
            if (args.service_name is not None) and (
                    args.service_name != service_name):
                continue

            if args.output == 'text':
                print('service[{}]'.format(s.getName()))

            for t in service_resources.Service.VALID_RESOURCE_TYPES:
                # Skip specific resource_types if the user has defined a filter
                if args.resource_type is not None and args.resource_type != t:
                    continue

                resourceTemplates = s.getResourceTemplatesByType(t)

                if args.output == 'text':
                    print('  resource_type[{}] num_items[{}]'.format(
                        t, len(resourceTemplates)))

                # Print the resource files
                for rt in s.getResourceTemplatesByType(t):
                    if args.output == 'text':
                        print('    ' + str(rt))
                    resources.append({
                        'resource_type': t,
                        'service_name': service_name,
                        'resource_name': rt.getName(),
                        'template': rt.getTemplate(),
                        'vars': rt.getVars(),
                    })

        if args.output == 'json':
            print(json.dumps(resources))
        if args.output == 'yaml':
            print(yaml.safe_dump(resources))
