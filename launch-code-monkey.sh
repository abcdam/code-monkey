#!/bin/bash

script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/../sammelsurium/routines/helper.sh"

CONTEXT_DIR=$(realpath "$1") || throw "First Argument: Context directory couldn't be parsed."
[ -n "$2" ] && IMG_NAME=$2 || throw "Second Argument: No image name provided."
[ -d $CONTEXT_DIR ] || throw "Directory '$CONTEXT_DIR' existence check failed."

# given docker image name must fully match an available docker image
docker image ls | awk 'NR > 1 {print $1}' | grep "^$IMG_NAME$" 1>/dev/null \
    || throw "Docker image name '$IMG_NAME' couldn't be retrieved from local registry "

SHARED_DIR='./shared-dir/data'
EXPOSED_DIR="$SHARED_DIR/docs"
mkdir -p "$EXPOSED_DIR"

# make user given code dir discoverable by open-webui 
rsync -hvrP --exclude .git/ $CONTEXT_DIR $EXPOSED_DIR

OLLAMA_DIR="$SHARED_DIR/ollama"
mkdir -p "$OLLAMA_DIR"
CONTAINER_NAME=code-monkey-webui

docker run --rm --detach --publish 3000:8080 --runtime=nvidia --gpus=all --env DATA_DIR=/tmp/data --volume "$OLLAMA_DIR:/root/.ollama" -v "$SHARED_DIR:/tmp/data" --name $CONTAINER_NAME $IMG_NAME

docker container logs -f $CONTAINER_NAME
