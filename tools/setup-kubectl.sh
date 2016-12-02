#!/bin/bash
# https://gist.github.com/FrankDeGroot/8cbec84eabfebcf2f2e7

echo "Finding latest kubectl"
# LATEST=$(wget -qO- https://github.com/kubernetes/kubernetes/releases/latest | awk -F '[<>]' '/href="\/kubernetes\/kubernetes\/tree\/.*"/ { match($0, "tree/([^\"]+)",a); print a[1] }' | head -1)
LATEST=$(curl -Ls https://github.com/kubernetes/kubernetes/releases/latest | xargs -0 echo | awk -F '[<>]' '/href="\/kubernetes\/kubernetes\/tree\/.*"/ { match($0, "tree/([^\"]+)",a); print a[1] }' | head -1)

echo "Getting kubectl-$LATEST"
sudo curl -o /usr/bin/kubectl http://storage.googleapis.com/kubernetes-release/release/$LATEST/bin/linux/amd64/kubectl
sudo chmod 755 /usr/bin/kubectl
