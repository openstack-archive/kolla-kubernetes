LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
PIPELINE="$5"
sudo docker images | awk '{if($1!="REPOSITORY"){print $1 ":" $2}}' | sort -u > $LOGS/docker_images.txt
cat $LOGS/docker_images.txt | grep kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $LOGS/docker_kolla_images.txt
cat $LOGS/docker_images.txt | grep -v kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $LOGS/docker_kubernetes_images.txt

if [ "x$PIPELINE" == "xperiodic" ]; then
    sudo docker save -o $WORKSPACE/UPLOAD_CONTAINERS/kubernetes.tar $(cat $LOGS/docker_kubernetes_images.txt)
    sudo docker save -o $WORKSPACE/UPLOAD_CONTAINERS/$DISTRO-$TYPE-$CONFIG.tar $(cat $LOGS/docker_kolla_images.txt)
    sudo chown $USER $WORKSPACE/UPLOAD_CONTAINERS/*
    chmod 644 $WORKSPACE/UPLOAD_CONTAINERS/*
    bzip2 $WORKSPACE/UPLOAD_CONTAINERS/kubernetes.tar
    bzip2 $WORKSPACE/UPLOAD_CONTAINERS/$DISTRO-$TYPE-$CONFIG.tar
    cp $LOGS/docker_kubernetes_images.txt $WORKSPACE/UPLOAD_CONTAINERS/kubernetes-containers.txt
    cp $LOGS/docker_kubernetes_images.txt $WORKSPACE/UPLOAD_CONTAINERS/$DISTRO-$TYPE-$CONFIG-containers.txt
fi
