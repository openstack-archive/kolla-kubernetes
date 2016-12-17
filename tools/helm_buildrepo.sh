#!/bin/bash

set -e

REPODIR="$1"

REPOPORT="$2"

REPONAME="$3"

if [ "x$REPODIR" == "x" ]; then
    echo You must specify a repo dir.
    exit 1
fi

mkdir -p "$REPODIR"
helm repo index "$REPODIR"

if [ "x$REPOPORT" == "x" ]; then
    REPOPORT=10191
fi

if [ "x$REPONAME" == "x" ]; then
    REPONAME=kollabuild
fi

helm serve --address "127.0.0.1:$REPOPORT" --repo-path "$REPODIR" &
export PID=$!
trap "kill $PID" TERM

set +e
count=0
while true; do
  curl -f http://localhost:"$REPOPORT" && break
  [ $count -ge 100 ] && echo Failed to start. && exit -1
  count=$((count+1))
  sleep 1
  echo Waiting for server to start.
done
set -e

helm repo add "$REPONAME" http://localhost:"$REPOPORT"

wait $PID
