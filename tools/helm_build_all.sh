#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

REPODIR="$1"

if [ "x$REPODIR" == "x" ]; then
    echo You must specify a repo dir.
    exit 1
fi

$DIR/helm_prebuild_microservices.py
$DIR/helm_build_microservices.py "$REPODIR"

helm repo index "$REPODIR"
helm repo update

$DIR/helm_prebuild_services.py
$DIR/helm_build_services.py "$REPODIR"

helm repo index "$REPODIR"
helm repo update

$DIR/helm_prebuild_compute_kits.py
$DIR/helm_build_compute_kits.py "$REPODIR"

helm search | grep '^kollabuild/'
