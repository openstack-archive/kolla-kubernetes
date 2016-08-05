.. private-registry:

==============================================
Kolla Kubernetes Private Docker Registry Guide
==============================================

This guide documents how to configure the authentication and use of a
private registry within a Kubernetes cluster.  The official Kubernetes
documentation may be found `here
<http://kubernetes.io/docs/user-guide/images/#configuring-nodes-to-authenticate-to-a-private-repository>`_.
Please note that several methods exist, and more than one may work for
your setup.

`Specifying ImagePullSecrets on a Pod
<http://kubernetes.io/docs/user-guide/images/#specifying-imagepullsecrets-on-a-pod>`_
is the one method which will work across all Kubernetes installations,
regardless of the cloud provider or mechanism for automatic node
replacement.  This is the recommended configuration.


How It Works
============

There are two steps:

- Create an ImagePullSecret.  These instructions may differ based on
  the docker registry provider.  The two types of registry providers
  currently covered by this guide include:

  - Standard Docker Registry with Username/Password Authentication
  - GCR Google Container Registry

- Patch the Kubernetes default service-account to add a reference to
  the ImagePullSecret.  By default and unless configured otherwise,
  all Kubernetes pods are created under the default service-account.
  Pods under the default service-account use the ImagePullSecret
  credentials to authenticate and access the private docker registry.


Create the ImagePullSecret
==========================

Based on the docker registry provider, follow the appropriate section
below to create the ImagePullSecret.


Standard Docker Registry with Username/Password Authentication
--------------------------------------------------------------

A typical docker registry only requires only username/password
authentication, without any other API keys or tokens (e.g. Docker
Hub).

The Kubernetes official documentation for Creating a Secret with a
Docker Config may be found `here
<http://kubernetes.io/docs/user-guide/images/#creating-a-secret-with-a-docker-config>`_.

For the purposes of these instructions, create the ImagePullSecret to
be named ```private-docker-registry-secret```.

::

    # Create the ImagePullSecret named private-docker-registry-secret
    #   Be sure to replace the uppercase variables with your own.
    kubectl create secret docker-registry private-docker-registry-secret \
      --docker-server=DOCKER_REGISTRY_SERVER \
      --docker-username=DOCKER_USER \
      --docker-password=DOCKER_PASSWORD \
      --docker-email=DOCKER_EMAIL


GCR Registry with Google Service Account Authentication
-------------------------------------------------------

To allow any kubernetes cluster outside of Google Cloud to access the
GCR registry, the instuctions are a little more complex.  These
instructions have been modified from `stackoverflow
<https://stackoverflow.com/questions/36283660/creating-image-pull-secret-for-google-container-registry-that-doesnt-expire>`_.

- Go to the Google Developer Console > Api Manager > Credentials,
  click "Create credentials", and select "Service account key"
- Under "service account" select "new service account", name the new
  key "gcr", and select JSON for the key type.
- Click on "Create" and the service-account key will be downloaded to your disk.
- You may want to save the key file, since there is no way to
  re-download it from google.
- Rename the keyfile to be gcr-sa-key.json (GCR service account key),
  for the purposes of these instructions.
- Using the keyfile, create the kubernetes secret named ```private-docker-registry-secret```::

    # Create the docker-password from the file by stripping all
    #   newlines and squeezing whitespace.
    DOCKER_PASSWORD=`cat gcr-sa-key.json | tr -s '[:space:]' | tr -d '\n'`

    # Create a Kubernetes secret named "private-docker-registry-secret"
    kubectl create secret docker-registry private-docker-registry-secret \
      --docker-server "https://gcr.io" \
      --docker-username _json_key \
      --docker-email not@val.id \
      --docker-password="$DOCKER_PASSWORD"


Patch the Default Service-Account
=================================

Patch the Kubernetes default service-account to add a reference to the
ImagePullSecret, after which pods under the default service-account
use the ImagePullSecret credentials to authenticate and access the
private docker registry.

::

    # Patch the default service account to include the new
    #   ImagePullSecret
    kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"private-docker-registry-secret"}]}'

Now, your kubernetes cluster should have access to the private docker registry.

