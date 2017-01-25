docker images | awk '{if($1!="REPOSITORY"){print $1, $2}}' $WORKSPACE/logs/docker_images.txt
cat $WORKSPACE/logs/docker_images.txt | grep kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $WORKSPACE/logs/docker_kolla_images.txt
cat $WORKSPACE/logs/docker_images.txt | grep -v kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $WORKSPACE/logs/docker_kubernetes_images.txt
