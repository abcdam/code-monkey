#!/bin/bash
set -e
source '/usr/lib/helper-func.sh'

script_dir=$(dirname "$(realpath "$0")")
DEFAULT_IMG='code-assist:default'
CONTAINER_NAME='code-assist-owebui'
SHARED_DIR='./shared-dir/data'
OLLAMA_DIR="$SHARED_DIR/ollama"
LOGS="$script_dir/logs"
LOG_FILE_NAME="$(date +"%Y%m%d%H%M")_owebui.log"
LOG_FILE="$LOGS/$LOG_FILE_NAME"

build_img() {
    docker build -t "$IMG_NAME" "$script_dir/"
}

run_container() {
    repo_id=$(echo "$IMG_NAME" | cut -d ':' -f1)
    docker image ls | awk 'NR > 1 {print $1}' | grep -qE "^$repo_id$" \
        || throw "Docker image name '$IMG_NAME' couldn't be retrieved from local registry "
    
    mkdir -p "$OLLAMA_DIR"
    mkdir -p "$LOGS"

    if [ -n "$CONTEXT_PATH" ]; then
        EXPOSED_DIR="$SHARED_DIR/docs" && mkdir -p "$EXPOSED_DIR"
        # make user given code dir discoverable by open-webui 
        rsync -hvrP --exclude .git/ "$CONTEXT_DIR" "$EXPOSED_DIR"
    fi

    docker run                                      \
        --rm                                        \
        --detach                                    \
        --publish 3000:8080                         \
        --runtime=nvidia                            \
        --gpus=all                                  \
        --volume "$OLLAMA_DIR:/root/.ollama"        \
        --volume "$SHARED_DIR:/tmp/data"            \
        --env DATA_DIR=/tmp/data                    \
        --env-file "$script_dir/.env.dev"           \
        --env-file "$script_dir/.env.secrets"       \
        --name "$CONTAINER_NAME"                    \
        "$IMG_NAME"

    echo "tail -f $LOG_FILE"
    docker logs -f "$CONTAINER_NAME" >> $LOG_FILE 2>&1 & # background logging
    
    # if ttmux is installed/discoverable, launch a template session that shows live logs and an overview of gpu load
    which ttmux >/dev/null && ttmux -s code-complete -w primary -t 1 "watch -n 0.3 nvidia-smi" "tail -f $LOG_FILE"
}

while getopts "i:p:" opt; do
    case $opt in
        p|path)
            CONTEXT_PATH="$OPTARG"      \
            && [ ! -f "$CONTEXT_PATH" ] \
            && [ ! -d "$CONTEXT_PATH" ] \
            && throw "err: Given path '$CONTEXT_PATH' not a valid file or directory."
            ;;
        i|image)
            IMG_NAME="$OPTARG"
            ;;
        \?)
            throw "err: invalid flag: -$OPTARG"
            ;;
    esac
done

shift $((OPTIND -1))
IMG_NAME="${IMG_NAME:-$DEFAULT_IMG}"

selection=0
while [ "$#" -gt 0 ]; do
    case $1 in
        build) [ -z "$cmd_build" ]  \
                && cmd_build=1      \
                && selection=$((selection+cmd_build))
            ;;
        serve) [ -z "$cmd_serve" ]  \
                && cmd_serve=2      \
                && selection=$((selection+cmd_serve))
            ;;
        restart) selection=restart && break
            ;;
        *) warn_ok "warn: command '$1' not supported"
            ;;
    esac
    shift
done

case $selection in
    0) throw "err: no valid command passed.";;
    1) echo "Building image.." && build_img;;
    2) echo "Launching container.." && run_container;;
    3) echo "Building image and launching container.." && build_img && run_container;;
    restart) 
        docker container stop $CONTAINER_NAME 2>/dev/null || warn_ok "warn: container '$CONTAINER_NAME' not running, starting now.."
        run_container
        ;;
    *) echo 'wat⸮';;
esac