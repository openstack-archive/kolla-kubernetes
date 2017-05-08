LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$5"
PIPELINE="$6"

if [ "x$DISTRO" == "xcentos" ]; then
    sudo find /var/cache/yum/
fi

if [ "x$PIPELINE" == "xperiodic" -a "x$DISTRO" == "xcentos" ]; then
    echo
fi
