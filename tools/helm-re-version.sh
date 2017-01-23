#!/bin/bash -xe
# Usage: helm-re-version.sh <old_version> <new_version>

find helm -name \*.yaml -print0 | xargs -0 sed -i '' -e s/$1/$2/g
find tools -name \*.sh -print0 | xargs -0 sed -i '' -e s/$1/$2/g
find tests -name \*.sh -print0 | xargs -0 sed -i '' -e s/$1/$2/g
