.. _mariadb-guide:

=============================
Memcached in Kolla-Kubernetes
=============================

Overview
========

`Memcached <https://memcached.org/>_ is the default persistant cache for a
`Kolla-Kubernetes cluster.

Preparation and Deployment
==========================

Memcached is self-sufficient, thus it's one of the first things you want to
start while installing.

Memcache does not require bootstrapping.  To create the Replication Controller
that will keep Memcached running::

    kolla-kubernetes start memcached

Verify Operation
================

To find the IP address of the kubernetes service so you can test for
functionality on a machine inside of the Kubernetes cluster (e.g. running
Kube-proxy) but not running as a container::

    kubectl get svc memcached

Once you know the IP address and port, you can check to see if memcached is
responding to requests by replacing <ADDRESS> with the address of the
memcached service::

    echo "stats settings" | nc <ADDRESS> 11211

You should see output looking like this:::

    STAT maxbytes 67108864
    STAT maxconns 1024
    STAT tcpport 11211
    STAT udpport 11211
    STAT inter 0.0.0.0
    STAT verbosity 2
    STAT oldest 0
    STAT evictions on
    STAT domain_socket NULL
    STAT umask 700
    STAT growth_factor 1.25
    STAT chunk_size 48
    STAT num_threads 4
    STAT num_threads_per_udp 4
    STAT stat_key_prefix :
    STAT detail_enabled no
    STAT reqs_per_event 20
    STAT cas_enabled yes
    STAT tcp_backlog 1024
    STAT binding_protocol auto-negotiate
    STAT auth_enabled_sasl no
    STAT item_size_max 1048576
    STAT maxconns_fast no
    STAT hashpower_init 0
    STAT slab_reassign no
    STAT slab_automove 0
    STAT lru_crawler no
    STAT lru_crawler_sleep 100
    STAT lru_crawler_tocrawl 0
    STAT tail_repair_time 0
    STAT flush_enabled yes
    STAT hash_algorithm jenkins
    STAT lru_maintainer_thread no
    STAT hot_lru_pct 32
    STAT warm_lru_pct 32
    STAT expirezero_does_not_evict no
    END

Debug an Instance
=================

TODO: Fill in more details