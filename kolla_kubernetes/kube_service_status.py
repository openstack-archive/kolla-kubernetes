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

import re

from oslo_log import log

from kolla_kubernetes.utils import ExecUtils
from kolla_kubernetes.utils import YamlUtils

LOG = log.getLogger(__name__)


class KubeResourceTypeStatus(object):

    def __init__(self, service_obj, resource_type):

        # Check input args
        if resource_type == 'disk':
            LOG.warning('resource_type disk is not supported yet')
            return

        # Initialize internal vars
        self.service_obj = service_obj
        self.resource_type = resource_type

        self.resource_templates = []

        self.doTemplateAndCheck()

    def asDict(self):
        res = {}
        res['meta'] = {}
        res['meta']['service_name'] = self.service_obj.getName()
        res['meta']['resource_type'] = self.resource_type

        res['results'] = {}
        res['results']['status'] = self.getStatus()

        res['xdetails'] = {}  # add 'x' for sort order and xtra-details

        res['xdetails']['templates'] = []
        for kr in self.resource_templates:
            res['xdetails']['templates'].append(kr.asDict())
        return res

    def getStatus(self):
        for krt in self.resource_templates:
            if krt.getStatus() == 'error':
                return 'error'
        return 'ok'

    def doTemplateAndCheck(self):
        """Checks service resource_type resources in Kubernetes

        For each resourceTemplate of resource_type
          Process the template (which may contain a stream of yaml definitions)
          For each individual yaml definition
            Send to kubernetes
            Compare input definition to output status (do checks!)
            Note: This is kube check only.  Other subcommands should
            take care of application specific health checks (e.g. port checks)
        Summarize all of the above into a results dict
        Prints results dict to stdout as yaml status string
        """

        resourceTemplates = self.service_obj.getResourceTemplatesByType(
            self.resource_type)
        for rt in resourceTemplates:
            file_ = rt.getTemplatePath()

            # Skip unsupported script templates
            if file_.endswith('.sh.j2'):
                LOG.warning('Shell templates are not supported yet. '
                            'Skipping processing status of {}'.format(file_))
                continue

            krt = KubeResourceTemplateStatus(
                self.service_obj, self.resource_type, rt)
            self.resource_templates.append(krt)


class KubeResourceTemplateStatus(object):
    """KubeResourceTemplateStatus

       A KubeResourceTemplateStatus is a jinja template, which when
       processed may generate a stream of KubeResourceYamlStatus definitions
       separated by "^---".  In most cases, the output consists of a
       single KubeResourceYamlStatus blob.  However, sometimes the template
       may print nothing or whitespace (NO-OP).
    """

    def __init__(self, service_obj, resource_type,
                 resource_template_obj):

        # Initialize internal vars
        self.service_obj = service_obj
        self.resource_type = resource_type
        self.resource_template_obj = resource_template_obj

        self.errors = []
        self.oks = []
        self.kube_resources = []

        self.doCheck()

    def asDict(self):
        res = {}
        res['meta'] = {}
        res['meta']['template'] = self.resource_template_obj.getTemplatePath()

        res['results'] = {}
        res['results']['status'] = self.getStatus()
        res['results']['errors'] = self.errors
        res['results']['oks'] = self.oks

        res['xdetails'] = {}  # add 'x' for sort order and xtra-details
        res['xdetails']['segments'] = []
        for kr in self.kube_resources:
            res['xdetails']['segments'].append(kr.asDict())
        return res

    def getStatus(self):
        if len(self.errors) != 0:
            return 'error'
        for kr in self.kube_resources:
            if kr.getStatus() != 'ok':
                return 'error'
        return 'ok'

    def doCheck(self):

        # Build the templating command
        cmd = "kolla-kubernetes resource-template {} {} {}".format(
            'create', self.resource_type,
            self.resource_template_obj.getName())

        # Execute the command to get the processed template output
        template_out, err = ExecUtils.exec_command(cmd)

        # Skip templates which which produce no-ops (100% whitespace)
        #   (e.g. pv templates for AWS should not use persistent
        #   volumes because AWS uses experimental
        #   auto-provisioning)
        if (err is not None):
            self.errors.append(
                'error processing template file: {}'.format(str(err)))
            return
        elif re.match("^\s+$", template_out):
            msg = "template {} produced empty output (NO-OP)".format(
                self.resource_template_obj.getTemplatePath())
            self.oks.append(msg)
            return

        # If the template output produces a stream of yaml documents
        # which are then piped to kubectl, then we will receive a
        # stream of reports separated by "\n\n".  Split on "\n\n" and
        # process each result individually.  The overall result is the
        # merged output.
        definitions = re.split("^---", template_out, re.MULTILINE)
        for definition in definitions:
            kr = KubeResourceYamlStatus(definition)
            self.kube_resources.append(kr)


class KubeResourceYamlStatus(object):
    """Class represents a single Kube resource yaml blob

    Implements functions to send the blob to "kubectl describe -f -",
    and evaluate the returned info text.
    """

    def __init__(self, kube_resource_definition_yaml):
        # Check input args
        assert len(kube_resource_definition_yaml) > 0

        # Initialize internal vars
        self.y = YamlUtils.yaml_dict_from_string(kube_resource_definition_yaml)
        self.definition = kube_resource_definition_yaml

        self.errors = []
        self.oks = []

        self.doDescribeAndCheck()

    def asDict(self):
        res = {}
        res['meta'] = {}
        res['meta']['name'] = self.getName()
        res['meta']['kind'] = self.getKind()
        res['results'] = {}
        res['results']['status'] = self.getStatus()
        res['results']['errors'] = self.errors
        res['results']['oks'] = self.oks
        return res

    def getKind(self):
        if self.y is None:  # this yaml segment may be empty (comments-only)
            return ""
        assert 'kind' in self.y
        return self.y['kind']

    def getName(self):
        if self.y is None:  # this yaml segment may be empty (comments-only)
            return ""
        assert 'metadata' in self.y
        assert 'name' in self.y['metadata']
        return self.y['metadata']['name']

    def getStatus(self):
        if len(self.errors) == 0:
            return 'ok'
        else:
            return 'error'

    def doDescribeAndCheck(self):

        # This yaml segment may be empty (comments-only)
        if self.y is None:
            self.oks.append('Yaml segment is empty of content and perhaps '
                            'only contains comments')
            return  # Allow to succeed

        # Create the command to send this single resource yaml blob to
        # kubectl to query its existence.
        cmd = ('echo \'{}\' | kubectl describe -f -'.format(
            self.definition.replace("'", "'\\''")))  # escape for bash

        out, err = ExecUtils.exec_command(cmd)

        # Check if kubectl returns non-zero exit status
        if err is not None:
            self.errors.append('Either resource does not exist, '
                               'or invalid resource yaml')
            return

        # For all resource types, check the Name to verify existence
        name = KubeResourceYamlStatus._matchSingleLineField('Name', out)
        if name is None or name != self.getName():
            self.errors.append(
                'No resource with name {} exists'.format(self.getName()))
        else:
            self.oks.append(
                'Verified resource with name {} exists'.format(self.getName()))

        # For PersistentVolumes and PersistentVolumeClaims
        if self.getKind() == 'PersistentVolume' or (
            self.getKind() == 'PersistentVolumeClaim'):

            # Verify that the PV/PVC is bound
            status = KubeResourceYamlStatus._matchSingleLineField(
                'Status', out)
            if status is None or status != "Bound":
                self.errors.append("{} not Bound".format(self.getKind()))
            else:
                self.oks.append("{} Bound".format(self.getKind()))

        # For Services
        if self.getKind() == 'Service':
            # Verify the service has an IP
            ip = KubeResourceYamlStatus._matchSingleLineField('IP', out)
            if ip is None or len(ip) == 0:
                self.errors.append("{} has no IP".format(self.getKind()))
            else:
                self.oks.append("{} has IP".format(self.getKind()))

        # For ReplicationControllers
        # Replicas:       1 current / 1 desired
        # Pods Status:    1 Running / 0 Waiting / 0 Succeeded / 0 Failed
        if self.getKind() == 'ReplicationController':

            # Verify the rc has the right number of replicas
            replicas = KubeResourceYamlStatus._matchSingleLineField(
                'Replicas', out)
            if replicas is None:
                self.errors.append(
                    "{} replicas not found".format(self.getKind()))
            else:
                self.oks.append(
                    "{} replicas found".format(self.getKind()))
                replicas_detail = KubeResourceYamlStatus._matchReturnGroups(
                    '^(\d+) current / (\d+) desired', replicas)
                if replicas_detail is not None:
                    current, desired = replicas_detail
                    if current != desired:
                        self.errors.append(
                            "current != desired: {}".format(replicas))
                    else:
                        self.oks.append(
                            "current == desired: {}".format(replicas))

            # Verify the rc has the right number of pod_status
            pod_status = KubeResourceYamlStatus._matchSingleLineField(
                'Pods Status', out)
            if pod_status is None:
                self.errors.append(
                    "{} pod_status not found".format(self.getKind()))
            else:
                self.oks.append(
                    "{} pod_status found".format(self.getKind()))

                pod_status_detail = KubeResourceYamlStatus._matchReturnGroups(
                    '^(\d+) Running / (\d+) Waiting /'
                    ' (\d+) Succeeded / (\d+) Failed', pod_status)
                if pod_status_detail is not None:
                    running, waiting, succeeded, failed = pod_status_detail
                    if (int(running) == 0 or int(waiting) > 0 or (
                            int(failed) > 0)):
                        self.errors.append(
                            "pod_status has errors {}".format(pod_status))
                    else:
                        self.oks.append(
                            "pod_status has no errors: {}".format(pod_status))

    @staticmethod
    def _matchSingleLineField(field_name, haystack):
        """Returns field name's value"""

        # Initial checks
        assert field_name is not None
        if haystack is None:
            return None

        # Execute the Search
        match = re.search('^{}:\s+(?P<MY_VAL>.*)$'.format(field_name),
                          haystack,
                          re.MULTILINE)

        # Check the value
        if match is None:
            return None
        else:
            return match.group('MY_VAL').strip()

    @staticmethod
    def _matchReturnGroups(regex, haystack):
        """Returns all groups matching regex"""

        # Initial checks
        assert regex is not None
        if haystack is None:
            return None

        # Execute the Search
        match = re.search(regex,
                          haystack,
                          re.MULTILINE)

        # Check the value
        if match is None:
            return None
        else:
            return match.groups()
