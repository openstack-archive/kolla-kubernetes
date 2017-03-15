=============================
Kolla-kubernetes Architecture
=============================

OpenStack deployment requires multiple sequential steps to occur in workflow
like fashion. This puts the onus on Kubernetes to handle dependency management
and task ordering for each OpenStack service, which it currently doesn't. Using
the kolla-kubernetes fencing pod [1] and etcd-operator [2] as an examples, the
community will evaluate adding Kubernetes Operators [3] as a means of handling
the deployment of OpenStack.

In addition, there will be an effort to use the Kubernetes native package
manager, the Helm project [4]. Kolla-kubernetes will evaluate using Helm charts
as a means for making each OpenStack service available in the native Kubernetes
ecosystem and increase consumability of Kolla containers in real world
deployments and across communities.

Problem description
===================

In order to execute the OpenStack day 1 and day 2 workflows (deploy, upgrade,
and reconfigure), the community needs a way to handle running a series of tasks
in a certain order.  Kubernetes does not natively support workflow operations.

OpenStack as a whole is highly customizable and flexible.  A deployment tool
needs to be equally customizable and flexible in order for a user to get
the most benefit from it.

Proposed change
===============

1. The kolla-kubernetes community will write Kubernetes Operators in **Python** as
part of the 1.0 release and revisit writing them in **Go** at a later date. The
reason for this is because Go lacks the ecosystem required by the TC in order to
allow for it to be used as part of OpenStack. Specifically, it has to do with
tools and code distribution.

2. The kolla-kubernetes community will write Helm charts for each of the OpenStack
services.

3. The kolla-kubernetes community will implement Dependency Init Containers.

Dependencies
------------

- Helm >= v2.0
- Kubernetes >= 1.4

Dependency Init Container
=========================

The dependency init container is a Kubernetes Init container object.  The init
container will be the first container run in a pod and its job check if its safe
for a service to run. This layer is great for solving low level dependency
issues that operators are overkill for doing.

A good example of this is openvswitch needing to wait until ovs-db is running
in order to proceed.

Dependency List for the Keystone Pod
------------------------------------

Init container for keystone pod would be blocked until these dependencies are
met:
  - MariaDB pod is ready
  - Keystone bootstrap job is done
  - Keystone configmap is present

After these conditions are met, the init container is marked as ready and
keystone pod can be deployed.

Kubernetes Operator
===================

*Kubernetes Controller* - A Kubernetes Controller is a piece of code that
manages the lifecycle of a complex application [5].
*Kubernetes Operator* - A Kubernetes Operator is defined as a containerized
Kubernetes Controller that uses the Kubernetes ThirdPartyResource [6]. The
Kubernetes Operator is meant to be directed by input, configuration, and action
from the user.

The Kubernetes Operator for deploying Keystone will perform the following tasks:
  1. Check Mariadb exists
  2. Check if Keystone exists
  3. Read Keystone configuration file from the Kubernetes ThirdPartyResource and
     register it as a configmap
  4. Perform any user directed actions from the Kubernetes ThirdPartyResource
  5. Use Helm to run a Kubernetes Job to create the Keystone database
  6. Use Helm to run a Kubernetes Job to create the users and roles
  7. Execute any additional startup tasks to bring the service to a ready state
  8. Use Helm to run Kubernetes pods for Keystone
  9. The Dependency Init Container determines its safe to run Keystone
  10. The Keystone pod starts

User perspective of a Kubernetes Operator
------------------------------------------

OpenStack lifecycle management is a workflow and Kubernetes Operators are the
implementation of it. However, using a kubernetes Operator needs to be optional
because a user may want to handle all the necessary lifecycle steps by hand.
Therefore, the Kubernetes Operator needs to be detached from the services
themselves so that it can be flexible.

Code Outline
------------

The Controller code will live in the kolla-kubernetes repo. The Kubernetes
Operator container(s) will be added as kolla image(s) and exist in the
kolla-kubernetes repo.

Layering
========

The kolla-kubernetes project is broken down into multiple consumable building
blocks. The building blocks are referred to as **layers**.

**layer** - A layer in kolla-kubernetes has the following properties:
              1. Optional - it can be skipped or turned off by an operator
              2. Performs a specific task
              3. All layers can be used for deployment

The diagram below is a representation of option 1 outlined in the
Kolla-kubernetes Design Options section.

As an example, a user needs the ability to choose the layer that best fits their
needs and preferences. That could mean skipping all upper layers and using layer
2.1 for deployment, but using layer 4 for upgrades. Also, a user could jump in
at layer 5 for deployment, then use layer 3 for upgrades or other lifecycle
operations.
   _____________________
  |      OpenStack      |
  | Kubernetes Operator | layer 5 - The Kubernetes Operator that will have
  |_________  __________|           oversight of all the other Kubernetes
            ||                      Operators
   _________\/__________
  |      Service        |
  | Kubernetes Operator | layer 4 - Executes Helm packages for a service.
  |_________  __________|
            ||
   _________\/__________
  |                     |
  |    Helm Package     | layer 3 - Organizes the Kubernetes resources for each
  |_________  __________|           pod
            ||
   _________\/__________
  |                     |
  | Kubernetes resource | layer 2 - Deploys pods/deployments/replication-
  |  _________________  |           controllers/daemon-sets for an OpenStack
  | | Dependency Init | |           service.
  | |     Container   | |layer 2.1- The Dependency Init Container checks to be
  | |_________________| |           sure dependencies are met before starting
  |_________  __________|           the service.
            ||
   _________\/__________
  |                     |
  |  OpenStack Service  | layer 1 - Kolla container
  |_____________________|

  5. OpenStack Kubernetes Operator (optional)
  4. Service Kubernetes Operator   (optional)
  3. Helm package                  (optional)
  2. Kubernetes service pod
    2.1 Dependency Init Container  (optional)
  1. OpenStack service

Kolla-kubernetes Design
=======================

The goal of this section is to provide the best kolla-kubernetes design so that
OpenStack lifecycle management will abide by the following principles:

  - Granular - Each resource is a well defined building block with a purpose
  - Consumable - Any user or project is able to easily use kolla-kubernetes
  - Flexible - The project is capable of being used in different ways
  - Customizable - The project is capable of adopting new use cases
  - Debuggable - It is clear when a resource is misbehaving and why

There were six models considered for how the community will deploy OpenStack on
Kubernetes.  Option 1 is highlighted below as the option the community found
the most appealing:

**Kolla-kubernetes will be using option 1 for its design model**
Option 1:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**service** (nova, keystone, neutron). There is a single OpenStack Kubernetes
operator that orchestrates each **service** Kubernetes Operator. The Dependency
Init Container exists as a Kubernetes Init object within a **service** pod.
The Dependency Init Container sits at the pod level to handle simpler dependency
resolution that isn't required by Kubernetes Operators.

  - This option provides a good amount of granularity in that there is a clear
    separation between the different layers of abstraction. *Every layer is*
    *optional and can be used for deployment*.

Other Options That Were Considered
----------------------------------

Option 2:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**service** (nova, keystone, neutron). There is a single OpenStack kubernetes
operator that orchestrates each **service** Kubernetes Operator.

  - This option provides a good amount of granularity in that there is a clear
    separation between the different layers of abstraction.  This could have
    more layers or it might be the right amount of abstraction a user is looking
    for.

Option 3:
There is a single OpenStack Kubernetes Operator that handles the deployment of
OpenStack.

  - Though the simplicity is appealing here, this option is concerning because
    it does not reflect the complexity, consumability, or granularity OpenStack
    lifecycle management requires.

Option 4:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**micro service** (nova-api, nova-conductor, nova-scheduler). Above that,
there is a Kubernetes Operator per **service** that controls the micro
service Kubernetes Operator. At the top level, there is a single OpenStack
Kubernetes Operator that orchestrates each **service** Kubernetes
Operator.

  - This option provides a high amount of granularity with every service being
    thinned out to the microservice level. This option will be the most costly
    in terms of code written since every service will have multiple Kubernetes
    Operators. Also, there needs to be an account of the additional layering
    being more granular.  More layers will add flexibility for the user.

Option 5:
There are multiple Kubernetes Operators. One Kubernetes Operator per each
**role** (compute, controller, networking, monitoring). There is a single
OpenStack Kubernetes Operator that orchestrates each **role** Kubernetes
Operator.

  - This option provides an average amount of granularity.  The roles would
    have to be completely customizable and exposed to the kubernetes operator.
    There isn't a defined layering to handle an individual lifecycle task for a
    specific service of a role in this model.

Option 6:
There is no OpenStack Kubernetes Operator. Only Kubernetes Operators for
Mariadb, rabbitmq, memcached, and to handle operations like back-ups or
disaster recovery.  Entrypoints are used for workflow management.

  - This is a simpler approach which subjects the orchestration layer to
    the pod level.

  - There is a concern here for trying to go too far to achieve maximum
    usability.  In Kolla's past, this has shown to create a lack of
    complexity and flexibility which are both required for an OpenStack
    deployment.

  - OpenStack is a complex application where day 2 operations demand a lot of
    care. If we handle complex operations at layer 1 (in the diagram), the
    containers will have to each carry all logic required to perform all
    operations at run time. Therefore, a user can easily run into a situation
    where the cluster is expected to do something, but the code underneath does
    something else entirely.

  - Debugging is a huge pain in layer 1 because it is a challenge to know where
    the workflow failed and how it failed with the logic scattered across all
    the containers.

  - The visibility and consumability are difficult because like Kolla learned,
    deploying logic from the client side is more effective then having logic
    run server side. Operators are the client side controllers, while
    entrypoints are run in the containers (server side). Kolla has shown
    that client side logic is far more effective for deploying a complex tool
    like OpenStack because a user has more control over what is happening.

Workflow Example
================

As an example, if a user had a cluster with Keystone and MariaDB already running
and wanted to run Glance, this is what would occur at each layer:

  User  - The user creates a custom config file for glance-api and saves it in
          /etc/kolla/glance-api/config.json.

          Next, the user runs the OpenStack Kubernetes Operator and inputs the
          customized glance-api config file as part of the Kubernetes
          ThirdPartyResource. Glance-registry will use the default config file
          in this example.

Layer 5 - The OpenStack Kubernetes Operator will look at the config files and
          merge any changes overwriting the existing config files. Then, the
          Kubernetes Operator looks at what the user requested for deployment.

          The Kubernetes Operator checks if the cluster has deployed the
          service then resolves the dependencies required for the service to be
          deployed.

          The OpenStack Kubernetes Operator spawns the Glance Kubernetes
          Operator.

Layer 4 - The Glance Kubernetes Operator will gather the config data placed in
          its Kubernetes ThirdPartyResource and create ConfigMaps for the config
          files.

          The Glance Kubernetes Operator will use Helm to start a Kubernetes Job
          which creates the Glance DB user and password. Also, use Helm to run
          the Kubernetes Job that will create the Keystone user and password.

          Finally, the Glance Kubernetes Operator will run the Glance services
          using Helm.

Layer 3 - The Glance Helm package will run the glance-api and glance-registry
          pods based on the Glance kolla-kubernetes templates.

Layer 2 - The Kubernetes pods run glance-api and glance-registry as Deployments.
          The templates will map the configmaps to the location Kolla expects
          config files to appear.
        - The Dependency Init Container checks to be sure glance-api and
          glance-registry are safe to run. Once they are, the services start.

Layer 1 - The Kolla containers run. They each pick up the mounted config files
          and run their service.

Helm
====

Helm inserts kolla-kubernetes into the Kubernetes app distribution system. That
way, a Kubernetes Operator can search for and consume the pieces of OpenStack as
building blocks to assemble a real world deployment. The user experience is
better using the Kubernetes native distribution system. In addition, Helm
provides a templating engine to ensure the templates are flexible and to make
the templates easy to version.

OpenStack and Kubernetes are different communities.  In order to grow the
interop between the two, it makes sense for OpenStack to be distrubuted using
the Kubernetes native package manager.

Code Outline
------------

There will be a Helm chart for each OpenStack service [7].  The Helm charts will
premier in the kolla-kubernetes repo.  After reaching some stabilization, the
community can decide to publish the charts to the incubation directory in the
Kubernetes repo [8].

Implementation
==============

Community discussion etherpads [9][10].

Primary Assignee(s)
-------------------
  Ryan Hallisey (rhallisey)
  Steven Dake (sdake)
  Kevin Fox (kfox1111)
  Pete Birley (portdirect)
  Michal Jastrzebski (inc0)
  Mark Giles (mgiles)
  Takashi Sogabe (sogabe)
  Steve Wilkerson (srwilkers)
  Duong Ha-Quang (duonghq)
  Serguei Bezverkhi (sbezverk)
  Surya Prakash Singh (sp_)

  kolla-kubernetes team

  < add your name here >

Work Items
----------
1. Write Kubernetes Operators required to run OpenStack
2. Write scripts that will execute the Kubernetes Operator
3. Write Helm charts for OpenStack services
4. Adjust the CLI to work with Kubernetes Operators and Helm

<Please add new work items that are worth mentioning in the spec>

Documentation Impact
====================

< more docs >

References
==========

- [1] - https://review.openstack.org/#/c/383922/
- [2] - https://github.com/coreos/etcd-operator
- [3] - https://coreos.com/blog/introducing-operators.html
- [4] - https://github.com/kubernetes/helm
- [5] - https://coreos.com/blog/introducing-the-etcd-operator.html
- [6] - https://github.com/coreos/etcd-operator/blob/master/doc/design/arch.png
- [7] - https://github.com/sapcc/openstack-helm
- [8] - https://github.com/kubernetes/charts/tree/master/incubator
- [9] - https://etherpad.openstack.org/p/161115-kolla-kubernetes-cn-discussion
- [10] - https://etherpad.openstack.org/p/operator-base-class
