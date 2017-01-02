kolla_val_get_str
=================

Definition Description:
  Takes a search path of vals to look for, and a key and returns the first
  defined value.
Inputs:
  Values     - a dictionary tree to search.
  searchPath - a dictionary or a string with ':' seperated doted paths to
               crawl through Values
  key        - an optional string that is appended to each searchPath item.
Outputs:
  the string of the value requested
Example:
  {{- $valPath := ":global.kolla.a:global.kolla.b:global.kolla.c" }}
  {{- $c := dict "searchPath" $valPath "key" "my_setting" "Values" .Values }}
  {{- include "kolla_val_get_str $c }}


kolla_val_get_first
===================

Definition Description:
  Takes a search path of vals to look for, and a key and returns the first
  defined value.
Inputs:
  Values     - a dictionary tree to search.
  searchPath - a dictionary or a string with ':' seperated doted paths to
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
  {{- include "kolla_val_get_first" $c }}
  {{- if $localVals.bar }}
    someone set enable_some_feature to true!
  {{- end }}


kolla_val_get_single
====================

Definition Description:
  Takes a doted path of a val to look for, and returns the value.
Inputs:
  Values  - a dictionary tree to search.
  key     - a string with the doted path to search for
  retDict - Dictionary to store returned value in.
  retKey  - Key in the retDict to store the returned value in.
Outputs:
  retDict.<retKey> is set to the found value.
  retval in the calling dictionary is set to the found value.
Example:
  {{- $valPath := tuple "" "global.kolla.a" "global.kolla.b" "global.kolla.c" }}
  {{- $localVals := dict }}
  {{- $c := dict "searchPath" $valPath "key" "enable_some_feature" "retDict" $localVals "retKey" "bar"  "Values" .Values }}
  {{- include "kolla_val_get_first" $c }}
  {{- if $localVals.bar }}
    someone set enable_some_feature to true!
  {{- end }}
