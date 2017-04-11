kolla_val_get_*
===============

These macro's are intended to be used to lookup Values in a way that makes it
easy to set generic settings that cover multiple packages in one values file,
and then easily override them with more specific, service or microservice
level settings.

For example say you had:
  * searchPath = ":global.kolla.mariadb:global.kolla.all",
  * key = "enable_logging"
  * global.kolla.all.enable_logging = False in the <package>/values.yaml

The user could override the setting with their own values.yaml in 3 different
ways:
  * global.kolla.all.enable_logging = True - affects all kolla packages.
  * global.kolla.mariadb.enable_logging = True - True only for mariadb related
    microservices.
  * enable_logging=True for the specific microservice.

kolla_val_get_str
=================

Definition Description:
  Takes a search path of vals to look for, and a key and returns the first
  defined value.

  *note* This is generally the function you want to use unless you must retain
  the datatype for some reason.

Inputs:
  Values     - a dictionary tree to search.
  searchPath - a dictionary or a string with ':' separated doted paths to
               crawl through Values
  key        - an optional string that is appended to each searchPath item.
Outputs:
  the string of the value requested
Example:
  {{- $valPath := ":global.kolla.a:global.kolla.b:global.kolla.c" }}
  {{- $c := dict "searchPath" $valPath "key" "my_setting" "Values" .Values }}
  {{- include "kolla_val_get_str $c }}


kolla_val_get_raw
===================

Definition Description:
  Takes a search path of vals to look for, and a key and returns the first
  defined value.

  *note* Use this if you need to maintain the datatype.

Inputs:
  Values     - a dictionary tree to search.
  searchPath - a dictionary or a string with ':' separated doted paths to
               crawl through Values
  key        - an optional string that is appended to each searchPath item.
  retDict    - Dictionary to store returned value in.
  retKey     - Key in the retDict to store the returned value in.
Outputs:
  retDict.<retKey> is set to the first found value.
Example:
  {{- $valPath := tuple "" "global.kolla.a" "global.kolla.b" "global.kolla.c" }}
  {{- $localVals := dict }}
  {{- $c := dict "searchPath" $valPath "key" "enable_some_feature" "retDict" $localVals "retKey" "bar"  "Values" .Values }}
  {{- include "kolla_val_get_raw" $c }}
  {{- if $localVals.bar }}
    someone set enable_some_feature to true!
  {{- end }}


kolla_val_get_single
====================

Definition Description:
  Takes a doted path of a val to look for, and returns the value.

  *note* You probably should be using one of the other functions instead.

Inputs:
  Values  - a dictionary tree to search.
  key     - a string with the doted path to search for
  retDict - Dictionary to store returned value in.
  retKey  - Key in the retDict to store the returned value in.
Outputs:
  retDict.<retKey> is set to the found value.
  retval in the calling dictionary is set to the found value.
Example:
  {{- $localVals := dict }}
  {{- $c := dict "key" "global.kolla.a.enable_some_feature" "retDict" $localVals "retKey" "bar"  "Values" .Values }}
  {{- include "kolla_val_get_single" $c }}
  {{- if $localVals.bar }}
    someone set enable_some_feature to true!
  {{- end }}
