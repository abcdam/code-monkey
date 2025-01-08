#!/bin/bash
set -e
source '/usr/lib/helper-func.sh'

script_dir=$(dirname "$(realpath "$0")")
DEFAULT_IMG='code-assist:default'
CONTAINER_NAME='code-assist-owebui'
LOGS="$script_dir/logs"
LOG_FILE_NAME="$(date +"%Y%m%d%H%M")_owebui.log"
LOG_FILE="$LOGS/$LOG_FILE_NAME"
PRETTYSYNOP_BIN="$HOME/lib/pretty-synopsis.pl"


show_help() {
    
    SYNOPSIS=$(
        echo "Usage: $(basename "$0");; [OPTIONS] COMMAND;;"\
            "This script manages Docker container operations for a code assistance environment."
    )

    DESCRIPTION=$(
        echo "Options;;"\
                "-i;--image <name>;The name of the image in the local registry (default: $DEFAULT_IMG);;"\
    )

    COMMANDS=$(
        echo "Commands;;"\
                "build;Build the Docker image (default: $DEFAULT_IMG);;"\
                "serve;Launch the container;;"\
                "restart;Restart the container if already running or start it if not"
    )
    $PRETTYSYNOP_BIN --synopsis="$SYNOPSIS" --description="$DESCRIPTION"
    $PRETTYSYNOP_BIN --description="$COMMANDS"
}

build_img() {
    openssl req -x509 -nodes -days 365 -newkey rsa:2048     \
    -keyout configs/key.key                                 \
    -out configs/nginx_cert.crt                                   \
    -subj "/C=US/ST=State/L=City/O=Nginx-rp/CN=0.0.0.0" && \
    openssl x509 -in configs/nginx_cert.crt -noout -text
    docker compose up
}

run_container() {
    
    mkdir -p "$LOGS"

    docker run                                  \
        --rm                                    \
        --detach                                \
        --publish 1111:8080                     \
        --publish 4444:11434                    \
        --runtime=nvidia                        \
        --gpus=all                              \
        --volume /root/.ollama/models           \
        --volume /tmp/data/uploads              \
        --env DATA_DIR=/tmp/data                \
        --env-file "$script_dir/.env.dev"       \
        --env-file "$script_dir/.env.secrets"   \
        --name "$CONTAINER_NAME"                \
        "$IMG_NAME"

    echo "tail -f $LOG_FILE"
    docker logs -f "$CONTAINER_NAME" >> $LOG_FILE 2>&1 & # background logging
    
    # if ttmux is installed/discoverable, launch a template session that shows live logs and an overview of gpu load
    which ttmux >/dev/null && ttmux -s code-complete -w primary -t 1 "watch -n 0.3 nvidia-smi" "tail -f $LOG_FILE"
}

while getopts "i:h" opt; do
    case $opt in
        i|image)
            IMG_NAME="$OPTARG"
            ;;
        h|help)
            show_help && exit 0
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
    1) echo "Building image.."                          \
        && build_img
        ;;
    2) echo "Launching container.."                     \
        && run_container
        ;;
    3) echo "Building image and launching container.."  \
        && build_img                                    \
        && run_container
        ;;
    restart) 
        docker container stop $CONTAINER_NAME 2>/dev/null || warn_ok "warn: container '$CONTAINER_NAME' not running, starting now.."
        run_container
        ;;
    *) echo 'wat⸮';;
esac
