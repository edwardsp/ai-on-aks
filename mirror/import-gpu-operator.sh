#!/bin/bash

# get script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

git_repo=https://github.com/NVIDIA/gpu-operator.git
git_branch=release-23.9

# log in to acr
az acr login -n $ACR_NAME

# create random tmp dir
TMP_DIR=$(mktemp -d)
#pushd "$TMP_DIR"

git clone -b $git_branch $git_repo
cd gpu-operator/deployments/gpu-operator

chart_version=$(yq .version Chart.yaml)
image_tag_version=$(yq .appVersion Chart.yaml)

TEMP_FILE=$(mktemp)
$SCRIPT_DIR/get_repositories.py > "$TEMP_FILE"
while IFS= read -r line; do
    # Process each line here
    IFS=',' read -r path repository image version <<< "$line"
    if [ -z "$version" ]; then
        version=$image_tag_version
    fi
    if [ -z "$repository" ]; then
        continue
    fi

    echo "Processing $repository/$image:$version [ $path ]"

    # update the repository in the values.yaml
    yq_repository_path=".$(echo $path | tr '/' '.')respository"
    new_repository="$ACR_NAME.azurecr.io/$repository"
    
    # import the container to ACR
    docker pull $repository/$image:$version
    docker tag $repository/$image:$version $new_repository/$image:$version
    docker push $new_repository/$image:$version
done < "$TEMP_FILE"
rm "$TEMP_FILE"

sed -i "s#^\( *repository: \)\(.*\)#\1${ACR_NAME}.azurecr.io/\2#" values.yaml

helm package .
helm push gpu-operator-${chart_version}.tgz oci://$ACR_NAME.azurecr.io/helm

popd
rm -rf "$TMP_DIR"

for img in nvcr.io/nvidia/driver:535.86.10-ubuntu22.04; do
    docker pull $img
    docker tag $img $ACR_NAME.azurecr.io/$img
    docker push $ACR_NAME.azurecr.io/$img
done
