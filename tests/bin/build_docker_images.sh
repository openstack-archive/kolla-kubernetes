LOGS="$1"
sudo docker images | awk '{if($1!="REPOSITORY"){print $1, $2}}' | sort -u > $LOGS/docker_images.txt
cat $LOGS/docker_images.txt | grep kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $LOGS/docker_kolla_images.txt
cat $LOGS/docker_images.txt | grep -v kolla | sed 's@^kolla@docker.io/kolla@' | sort -u > $LOGS/docker_kubernetes_images.txt
