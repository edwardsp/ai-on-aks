#!/bin/bash

git_repo=https://github.com/kubernetes-sigs/node-feature-discovery.git
git_branch=release-0.16

# log in to acr
az acr login -n $ACR_NAME

# create random tmp dir
TMP_DIR=$(mktemp -d)
pushd $TMP_DIR

git clone -b $git_branch $git_repo
cd node-feature-discovery/deployment/helm/node-feature-discovery

chart_version=$(yq .version Chart.yaml)
image_tag_version=$(yq .appVersion Chart.yaml)

img=$(yq .image.repository values.yaml)
docker pull $img:$image_tag_version
docker tag $img:$image_tag_version $ACR_NAME.azurecr.io/$img:$image_tag_version
docker push $ACR_NAME.azurecr.io/$img:$image_tag_version

yq eval ".image.repository = \"${ACR_NAME}.azurecr.io/$img\"" -i values.yaml
helm package .
helm push node-feature-discovery-${chart_version}.tgz oci://$ACR_NAME.azurecr.io/helm

popd
rm -rf $TMP_DIR
