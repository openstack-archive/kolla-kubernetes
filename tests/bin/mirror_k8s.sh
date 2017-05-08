LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$5"
PIPELINE="$6"

if [ "x$DISTRO" == "xcentos" ]; then
    sudo ls /var/cache/yum/x86_64/7/kubernetes/packages/
fi

if [ "x$PIPELINE" == "xperiodic" -a "x$DISTRO" == "xcentos" ]; then

fi
