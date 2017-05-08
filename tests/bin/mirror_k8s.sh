LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$5"
PIPELINE="$6"

if [ "x$DISTRO" == "xcentos" ]; then
    sudo sed -i 's/keepcache=0/keepcache=1/' /etc/yum.conf
    sudo find /var/cache/yum/kubernetes/packages
fi

if [ "x$PIPELINE" == "xperiodic" -a "x$DISTRO" == "xcentos" ]; then
    echo
fi
