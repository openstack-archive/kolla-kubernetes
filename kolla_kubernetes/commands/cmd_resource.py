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
import copy
import json
import os
import subprocess
import sys
import tempfile
import yaml

from oslo_log import log

from kolla_kubernetes.commands.base_command import KollaKubernetesBaseCommand
from kolla_kubernetes.pathfinder import PathFinder
from kolla_kubernetes.service_resources import KollaKubernetesResources
from kolla_kubernetes.service_resources import Service
from kolla_kubernetes.utils import ExecUtils
from kolla_kubernetes.utils import FileUtils
from kolla_kubernetes.utils import JinjaUtils
from kolla_kubernetes.utils import YamlUtils

LOG = log.getLogger(__name__)
KKR = KollaKubernetesResources.Get()


class ResourceBase(KollaKubernetesBaseCommand):
    """Create, delete, or query status for kolla-kubernetes resources"""

    def get_parser(self, prog_name, skip_action=False):
        parser = super(ResourceBase, self).get_parser(prog_name)
        if not skip_action:
            parser.add_argument(
                "action",
                metavar="<action>",
                help=("One of [%s]" % ("|".join(Service.VALID_ACTIONS)))
            )
        parser.add_argument(
            "resource_type",
            metavar="<resource-type>",
            help=("One of [%s]" % ("|".join(Service.VALID_RESOURCE_TYPES)))
        )
        return parser

    def validate_args(self, args, skip_action=False):
        if not skip_action and args.action not in Service.VALID_ACTIONS:
            msg = ("action [{}] not in valid actions [{}]".format(
                args.action,
                "|".join(Service.VALID_ACTIONS)))
            raise Exception(msg)
        if args.resource_type not in Service.VALID_RESOURCE_TYPES:
            msg = ("resource_type [{}] not in valid resource_types [{}]"
                   .format(args.resource_type,
                           "|".join(Service.VALID_RESOURCE_TYPES)))
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

    def get_parser(self, prog_name, skip_action=False):
        parser = super(ResourceTemplate, self).get_parser(prog_name,
                                                          skip_action)
        parser.add_argument(
            "resource_name",
            metavar="<resource-name>",
            nargs='+',
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
            "-o",
            "--output",
            metavar="output",
            default="yaml",
            help=("Format output into one of [%s]" % (
                "|".join(['yaml', 'json'])))
        ),
        parser.add_argument(
            "-d",
            "--debug-container",
            metavar="container",
            dest='debug_container',
            action='append',
            help=("Assist in the debugging of the specified container")
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
        multi = len(args.resource_name) != 1
        multidoc = {
            'apiVersion': 'v1',
            'kind': 'List',
            'items': []
        }
        for resource_name in args.resource_name:
            service_name = KKR.getServiceNameByResourceTypeName(
                args.resource_type,
                resource_name)
            service = KKR.getServiceByName(service_name)
            rt = service.getResourceTemplateByTypeAndName(
                args.resource_type, resource_name)

            tmpargs = copy.deepcopy(vars(args))
            tmpargs['resource_name'] = resource_name
            variables = KKR.GetJinjaDict(service_name, tmpargs,
                                         args.print_jinja_keys_regex)

            # Merge the template vars with the jinja vars before processing
            variables['kolla_kubernetes'].update(
                {"template": {"vars": rt.getVars()}})

            # handle the debug option --print-jinja-vars
            if args.print_jinja_vars is True:
                print(YamlUtils.yaml_dict_to_string(variables),
                      file=sys.stderr)

            if args.resource_type == 'configmap' and \
               rt.getTemplate() == 'auto':
                nsname = 'kolla_kubernetes_namespace'
                cmd = "kubectl create configmap {} -o yaml --dry-run"
                cmd = cmd.format(resource_name)

                for f in PathFinder.find_config_files(resource_name):
                    cmd += ' --from-file={}={}'.format(
                        os.path.basename(f).replace("_", "-"), f)

                # Execute the command
                out, err = ExecUtils.exec_command(cmd)
                y = yaml.load(out)
                y['metadata']['namespace'] = variables[nsname]

                res = y
            else:
                # process the template
                raw_doc = JinjaUtils.render_jinja(
                    variables,
                    FileUtils.read_string_from_file(rt.getTemplatePath()))
                res = yaml.load(raw_doc)

            if args.debug_container is not None:
                y = res
                kind = y['kind']
                if kind not in ('PetSet', 'Deployment', 'Job', 'DaemonSet',
                                'ReplicationController', 'Pod'):
                    raise Exception("Template doesn't have containers.")
                pod = y
                if kind != 'Pod':
                    pod = y['spec']['template']
                alpha_init_containers = None
                annotation = 'pod.alpha.kubernetes.io/init-containers'
                if 'metadata' in pod and 'annotations' in pod['metadata'] and \
                   annotation in pod['metadata']['annotations']:
                    j = json.loads(pod['metadata']['annotations'][annotation])
                    alpha_init_containers = {}
                    for c in j:
                        alpha_init_containers[c['name']] = c
                containers = {}
                for c in pod['spec']['containers']:
                    containers[c['name']] = c
                for c in args.debug_container:
                    found = False
                    warn_msg = "WARNING: container [{}] already has a" + \
                               " command override."
                    warn_msg = warn_msg.format(c)
                    if alpha_init_containers and c in alpha_init_containers:
                        if 'command' in alpha_init_containers[c]:
                            print(warn_msg, file=sys.stderr)
                        if 'args' in alpha_init_containers[c]:
                            del alpha_init_containers[c]['args']
                        alpha_init_containers[c]['command'] = \
                            ['/bin/bash', '-c',
                             'while true; do sleep 1000; done']
                        found = True
                    if c in containers:
                        if 'command' in containers[c]:
                            print(warn_msg, file=sys.stderr)
                        if 'args' in containers[c]:
                            del containers[c]['args']
                        containers[c]['command'] = \
                            ['/bin/bash', '-c',
                             'while true; do sleep 1000; done']
                        found = True

                    if not found:
                        raise Exception("Failed to find container: %s" % c)

                if alpha_init_containers:
                    annotation = 'pod.alpha.kubernetes.io/init-containers'
                    v = alpha_init_containers.values()
                    pod['metadata']['annotations'][annotation] = json.dumps(v)
            multidoc['items'].append(res)

        if skip_and_return:
            if multi:
                return yaml.safe_dump(multidoc)
            else:
                return yaml.safe_dump(res)

        if args.output == 'json':
            if multi:
                print(json.dumps(multidoc, indent=4), end="")
            else:
                print(json.dumps(res, indent=4), end="")
        elif multi:
            print(yaml.safe_dump(multidoc))
        else:
            if args.debug_container is not None:
                print(yaml.safe_dump(res), end="")
            else:
                print(raw_doc, end="")


class Template(ResourceTemplate):
    """Jinja process kolla-kubernetes resource template files"""

    def get_parser(self, prog_name):
        parser = super(Template, self).get_parser(prog_name,
                                                  skip_action=True)
        return parser

    def validate_args(self, args):
        super(Template, self).validate_args(args, skip_action=True)


class Resource(ResourceTemplate):
    """Create kolla-kubernetes resources"""

    def validate_args(self, args):
        super(Resource, self).validate_args(args)
        if args.action not in ['create', 'delete', 'status']:
            msg = ("action [{}] currently not supported".format(
                args.action))
            raise Exception(msg)

    def _kind_to_cli(self, kind):
        kind_map = {
            'PetSet': 'petset',
            'Pod': 'pod',
            'ReplicationController': 'rc',
            'DaemonSet': 'daemonset',
            'Job': 'job',
            'Deployment': 'deployment',
            'ConfigMap': 'configmap',
            'Secret': 'secret',
            'Service': 'svc',
            'PersistentVolume': 'pv',
            'PersistentVolumeClaim': 'pvc',
        }
        if kind not in kind_map:
            msg = ("unknown template kind [{}].".format(kind))
            raise Exception(msg)
        return kind_map[kind]

    def _process_template(self, kind, namespace, template, names, action):
        nsflag = ""
        if kind != 'pv':
            nsflag = " --namespace={}".format(namespace)
        if action == 'create':
            with tempfile.NamedTemporaryFile() as tf:
                tf.write(template)
                tf.flush()
                s = "kubectl {} -f {}{}".format(
                    action, tf.name, nsflag)
                subprocess.call(s, shell=True)
                tf.close()
        elif action == "delete":
            s = "kubectl delete {} {}{}".format(
                kind, names, nsflag)
            subprocess.call(s, shell=True)
        elif action == 'status':
            s = "kubectl get {} {}{}".format(
                kind, names, nsflag)
            subprocess.call(s, shell=True)

    def _get_ns(self, y):
        template_ns = ''
        try:
            template_ns = y['metadata']['namespace']
        except Exception:
            pass
        return template_ns

    def take_action(self, args):
        tmpl = super(Resource, self).take_action(args, skip_and_return=True)
        y = yaml.load(tmpl)
        kind = y['kind']
        if kind == 'List':
            first_item = y['items'][0]
            ns = self._get_ns(first_item)
            type_map = {}
            for item in y['items']:
                if self._get_ns(item) != ns:
                    msg = "Bad template in list. Different namespaces."
                    raise Exception(msg)
                kind_cli = self._kind_to_cli(item['kind'])
                t = type_map.get(kind_cli)
                if t is None:
                    type_map[kind_cli] = t = []
                t.append(item['metadata']['name'])
            if args.action in ('status', 'delete'):
                for (kind_cli, names) in type_map.items():
                    self._process_template(kind_cli, ns, tmpl, ' '.join(names),
                                           args.action)
            else:
                self._process_template(self._kind_to_cli(first_item['kind']),
                                       ns, tmpl, '', args.action)

        else:
            ns = self._get_ns(y)
            self._process_template(self._kind_to_cli(kind),
                                   ns,
                                   tmpl, y['metadata']['name'],
                                   args.action)


class ResourceMap(KollaKubernetesBaseCommand):
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
                "|".join(Service.VALID_RESOURCE_TYPES)))
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

            for t in Service.VALID_RESOURCE_TYPES:
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
