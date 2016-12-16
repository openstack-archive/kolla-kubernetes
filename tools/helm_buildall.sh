#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

REPODIR="$1"

if [ "x$REPODIR" == "x" ]; then
    echo You must specify a repo dir.
    exit 1
fi

$DIR/helm_buildrepo.sh "$REPODIR" &
export PID=$!
trap "kill $PID" TERM

$DIR/helm_prebuild_microservices.py
$DIR/helm_build_microservices.py "$REPODIR"

helm repo index "$REPODIR"
helm repo update

#At this point you have a usable microservices repo.

$DIR/helm_prebuild_services.py
#helm_build_services.py - for each service package 'helm package <packagename>'

kill $PID

helm search | grep '^kollabuild/'
