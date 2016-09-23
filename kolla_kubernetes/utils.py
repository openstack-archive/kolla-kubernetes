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
import base64
import copy
import jinja2
import os
import re
import subprocess
import sys
import yaml

from oslo_log import log as logging

from kolla_kubernetes import pathfinder

LOG = logging.getLogger()

# Disable yaml short-form printing of aliases and anchors
yaml.SafeDumper.ignore_aliases = lambda self, data: True


def env(*args, **kwargs):
    for arg in args:
        value = os.environ.get(arg)
        if value:
            return value
    return kwargs.get('default', '')


class ExecUtils(object):

    @staticmethod
    def exec_command(cmd):
        """Executes command and returns tuple of (stdout, errorException)

        Callers should check for errorException == None
        """
        # TODO(modify): modify function to include stderr in output tuple
        cmd = cmd.strip()  # strip whitespace
        try:
            LOG.debug("executing cmd[{}]".format(cmd))
            res = subprocess.check_output(
                cmd, shell=True,
                executable='/bin/bash')
            res = res.strip()  # strip whitespace
            LOG.debug("returned[{}]".format(res))
            return (res, None)
        except subprocess.CalledProcessError as e:
            # Any non-zero exit code will result in a thrown exception
            # The stdout may be accessed with e.output
            # The exit code may be accessed with e.returncode
            return (e.output.rstrip(), e)


class FileUtils(object):

    @staticmethod
    def write_string_to_file(s, file):
        # Allows emit exception in error
        with open(file, "w") as f:
            f.write(s)
            f.close()

    @staticmethod
    def read_string_from_file(file):
        # Allows emit exception in error
        data = ""
        with open(file, "r") as f:
            data = f.read()
            f.close()
        return data


class JinjaUtils(object):

    @staticmethod
    def merge_configs_to_dict(config_files, initial_dict=None,
                              debug_regex=None):
        """Create the jinja2 dict, and resolve nested variables

        Returns a copy of the initial_dict, loaded with values from
        config_files.  Order matters.... later config files take precedence
        over earlier config files.

        debug_regex: A regex string, if defined, will print out any matching
        config keys as well as the configuration file it is read from.  Very
        useful for debugging.
          debug_regex = "mariadb"

        The above will print out every single key that matches mariadb.
        Complex regex is supported, since this is passed to re.match
        """

        # If there is an initial dictionary, merge its values first
        d = {}
        if initial_dict is not None:
            d.update(initial_dict)

        # Add the contents of each of the following ansible files into the
        # dict.
        for file_ in config_files:
            try:
                # Merge the configs
                x = YamlUtils.yaml_dict_from_file(file_)
                d.update(x)

                # Handle debug requests
                if debug_regex is not None:
                    print("FILE {}".format(file_), file=sys.stderr)
                    for k, v in x.items():
                        if re.match(debug_regex, k):
                            print("  {}: {}".format(k, v), file=sys.stderr)
            except Exception as e:
                LOG.warning('Unable to read file %s: %s', file_, e)
                raise e
        return d

    @staticmethod
    def render_jinja(dict_, template_str):
        """Render dict onto jinja template and return the string result"""
        name = 'jvars'

        def loader(n):
            if n == name:
                return template_str
            else:
                kkdir = pathfinder.PathFinder.find_kolla_kubernetes_dir()
                path = os.path.join(kkdir, n)
                f = open(path)
                d = f.read()
                f.close
                return d

        j2env = jinja2.Environment(
            loader=jinja2.FunctionLoader(loader))

        # Do not print type for bools "!!bool" on output
        j2env.filters['bool'] = TypeUtils.str_to_bool
        j2env.filters['min'] = min
        j2env.filters['b64encode'] = lambda x: \
            base64.b64encode(x.encode('ascii'))
        j2env.filters['b64decode'] = base64.b64decode
        j2env.filters['to_nice_yaml'] = lambda x: \
            yaml.safe_dump(x, default_flow_style=False) if x else ''

        # Add a "raise" keyword for raising exceptions from within jinja
        def jinja_raise(message):
            raise Exception(message)
        j2env.globals['raise'] = jinja_raise

        # Add a keyword for accessing KubeUtils from within jinja
        j2env.globals['KubeUtils'] = KubeUtils

        # Render the template
        rendered_template = j2env.get_template(name).render(dict_)
        return rendered_template + "\n"

    @staticmethod
    def dict_self_render(dict_):
        """Render dict_ values containing nested jinja variables

        Resolve these values by rendering the jinja dict on itself, as many
        times as jinja variables contain other jinja variables.  Stop when the
        rendered output stops changing.
        """
        d = copy.deepcopy(dict_)
        template = None
        for i in range(0, 10):
            template = YamlUtils.yaml_dict_to_string_jinja(d)
            rendered_template = JinjaUtils.render_jinja(d, template)
            d = YamlUtils.yaml_dict_from_string(rendered_template)
            if rendered_template.strip() == template.strip():
                return d
        raise Exception("Unable to fully render jinja variables")


class StringUtils(object):

    @staticmethod
    def pad_str(pad, num, s):
        return re.sub("^", (pad * num), s, 0, re.MULTILINE)


class TypeUtils(object):

    @staticmethod
    def str_to_bool(text):
        if not text:
            return False
        if text.lower() in ['true', 'yes']:
            return True
        return False


class YamlUtils(object):

    @staticmethod
    def yaml_dict_to_string(dict_):
        """Convert dict to string for human output"""
        # Use width=1000000 to prevent wrapping
        return yaml.safe_dump(dict_, default_flow_style=False,
                              width=1000000)

    @staticmethod
    def yaml_dict_to_string_jinja(dict_):
        """Convert dict to string for jinja processing

        Use this only for dict strings that jinja will process.  If
        you use the normal style instead of double-quote style, then
        yaml dump will escape all single quotes (') by doubling them
        up ('').  If jinja is to process the string, it will fail.
        Thus, change the quote style to avoid escaping single quote
        (').
        """
        # Use width=1000000 to prevent wrapping
        # Use double-quote style to prevent escaping of ' to ''
        return yaml.safe_dump(dict_, default_flow_style=False,
                              width=1000000, default_style='"')

    @staticmethod
    def yaml_dict_from_string(string_):
        # Use BaseLoader to keep "True|False" strings as strings
        return yaml.load(string_, Loader=yaml.loader.BaseLoader)

    @staticmethod
    def yaml_dict_normalize(dict_):
        # This is used to flip "True|False" typed values back to
        #   strings in a dict.
        return YamlUtils.yaml_dict_from_string(
            YamlUtils.yaml_dict_to_string(dict_))

    @staticmethod
    def yaml_dict_to_file(dict_, file_):
        s = YamlUtils.yaml_dict_to_string(dict_)
        return FileUtils.write_string_to_file(s, file_)

    @staticmethod
    def yaml_dict_from_file(file):
        s = FileUtils.read_string_from_file(file)
        return YamlUtils.yaml_dict_from_string(s)


class KubeUtils(object):

    @staticmethod
    def get_api_url(context):
        """Executes kubectl config view

        Returns either None or a string with API server url.

        Callers should check for returned string if it is not == None
        """
        res, code = ExecUtils.exec_command('kubectl config current-context')
        if code is not None:
            return ('', code)

        current_context = res

        res, code = ExecUtils.exec_command('kubectl config view')
        if code is not None:
            return ('', code)

        configuration = YamlUtils.yaml_dict_from_string(res)

        for cluster in configuration['clusters']:
            server = cluster['cluster']['server']
            context = cluster['name']
            if context == current_context:
                return server

        return None
