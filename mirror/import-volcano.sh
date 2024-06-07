#!/bin/bash

git_repo=https://github.com/volcano-sh/volcano.git
git_branch=release-1.9

# log in to acr
az acr login -n $ACR_NAME

# create random tmp dir
TMP_DIR=$(mktemp -d)
pushd $TMP_DIR

git clone -b $git_branch $git_repo
cd volcano/installer/helm/volcano

chart_version=$(yq .version Chart.yaml)
image_tag_version=$(yq .appVersion Chart.yaml)

sed -i "s#volcanosh#$ACR_NAME.azurecr.io/volcanosh#g" values.yaml
helm package .
helm push volcano-${chart_version}.tgz oci://$ACR_NAME.azurecr.io/helm

for img in vc-controller-manager vc-scheduler vc-webhook-manager; do
    docker pull docker.io/volcanosh/$img:$image_tag_version
    docker tag docker.io/volcanosh/$img:$image_tag_version $ACR_NAME.azurecr.io/volcanosh/$img:$image_tag_version
    docker push $ACR_NAME.azurecr.io/volcanosh/$img:$image_tag_version
done

popd
rm -rf $TMP_DIR
