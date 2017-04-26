Unmigrated Code
===============
Originally, kolla-kubernetes was based upon a jinja2 templating language
prior to Helm's introduction in to the kolla-kubernetes repository.  There
are a few services which have not yet been migrated to Helm which must be.

To make this easier on developers this directory still exists, however,
consider this directory to be essentially dead code **unless** working
on the migration.

 * swift
 * ceph-osd
 * keepalived
 * openvswitch-set-external-ip
 * elasticsearch
