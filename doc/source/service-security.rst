=========================================================================
Kubernetes Service Security... or, "Why is everything binding to 0.0.0.0"
=========================================================================

Traditional OpenStack installs have generally used split networks (either VLAN
segments or multi-port NICs and independent networks).  Kubernetes is designed
with the assumption that users are going to have a SDN fabric installed, of
which there are several different options using the CNI (Container Networking
Interface) API.  Both underlay and overlay networking options are available as
CNI services.

The Kubernetes fabric is mediated by the ``kube-proxy`` executable, thus even
software running on the node outside of a container is able to see Kubernetes
services.

How are ports exposed?
======================

While using ``HostNetwork=True`` (``Net=Host`` in Docker parlance), processes
running inside of a container are using the network namespace of the host,
meaning that network operations are not containerized and, as far as the TCP/IP
stack is concerned, the process is running in the parent host.  This means
that any process need to be just as careful about what ports are accessible
and how they are managing them as a process running outside of the container.
Thus, they must be careful which interface they listen to, who is allowed to
connect, etc.

In Kubernetes, containers default to ``HostNetwork=False`` and thus work
inside of the Kubernetes network framework.  They have no inbound ports
accessible by default unless you have set them to be exposed.

The normal way of exposing ports is via a Kubernetes Service.  A service has a
DNS alias exposed via SkyDNS (e.g. you are able to use ``mariadb`` to access
MariaDB) that points to the service IP address which is generally backed by a
Kubernetes Virtual IP.  Services can be either internal services or external
services.  Only services specifically marked as external services and
configured with either a LoadBalancer or a Ingress controller will be
accessible outside of the cluster.

Services can be exposed with a type of ``NodePort``, which means that a port
from a configurable range will be allocated for a service on each node on each
port will be configured to proxy, which is intended for users to be able to
configure their own external load balancers.

Thus, a server running inside of a container that doesn't have any services
exposed as ``NodePort`` can safely bind to 0.0.0.0 and rely on the underlying
network layer ensuring that attackers are unable to probe for it.

Containers that need to run as ``HostNetwork=True`` are unable to be exposed
as services but are still able to connect to other Kubernetes services.

What about other services running inside of the Kubernetes cluster?
===================================================================

By default, processes running on compute nodes within the cluster are part of
the same unrestricted network fabric.

Certain processes, Nova Compute nodes, for example, are running user workloads
out of the control of the cluster administrator and thus should not have
unrestricted access to the cluster.  There are two alternatives:

First, compute nodes can be provisioned outside of the Kubernetes cluster.
This is necessary if you are using compute nodes with KVM or Ironic and often
times the easiest approach.

Second, some of the CNI drivers (Calico being one example) can be configured
with NetworkPolicy objects to block access from certain nodes, which can
prevent compute nodes from seeing the internal services.  However, as
currently implemented, pods will still be accessible from the host on which
they are running, it is also necessary to schedule any containers with
``HostNetworking=True`` on dedicated hosts.
