==========================
Kolla-kubernetes use cases
==========================


Philosophy
==========

We will build kolla-kubernetes use cases with top-down approach.

First, we define some top-level use cases (very general)
Second, break down each use case into more specific use case
Third, match low-level use case to layer in Ryan's spec

We also need to decide how depth Kolla's users can interact with and then
limit use cases scope (and also number).


.. node:: this patch is not intended to be merged, but just as a modification
   tracking


Top-level use case
==================

1. install openstack with custom settings
2. upgrade openstack with custom settings
3. maintenence of system
4. adding new openstack services to existing deployment
