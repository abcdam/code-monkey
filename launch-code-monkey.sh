#!/bin/bash

DOCSPATH=$(realpath $1)
IMG_NAME=$2
[ ! $DOCSPATH ] && echo "missing docs path argument" && exit 1
[ ! $IMG_NAME ] && echo "missing image name" && exit 1

git clone https://github.com/open-webui/open-webui.git

CONTAINER_NAME=code-monkey-webui
mkdir -p ollama
docker run --rm --detach --publish 3000:8080 --runtime=nvidia --gpus=all --env WEBUI_AUTH=False --volume ./ollama:/root/.ollama -v ./open-webui:/app/backend/data -v $DOCSPATH:/app/backend/data/docs --name $CONTAINER_NAME $IMG_NAME

# this is a workaround to update ollama to latest version to fix a bug when offloading layers to gpu in mistral model

docker exec -it $CONTAINER_NAME kill -9 13
docker exec -it $CONTAINER_NAME curl -fsSL https://ollama.com/install.sh | sh
docker exec -it $CONTAINER_NAME ollama serve &
docker container logs $CONTAINER_NAME
