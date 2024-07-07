# code-monkey
consistent &amp; local llama3 instance deployer with system prompt geared towards minimalistic output generation

## Overview
- deployment of local code assistant
- it clones open-webui and replaces docker-compose.yaml and docker-compose.gpu.yaml with files in this repo
- For Nvidia GPU support (flawless execution on gtx1080)
    - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installing-the-nvidia-container-toolkit
    - it is expected for the host to have the right drivers installed
- to build deployer
    - cd into cloned repo dir
    - execute: `docker build -t <deployer_image_name> .`
- let deployer handle the rest:
    - execute: `docker run -v /var/run/docker.sock:/var/run/docker.sock <deployer_image_name>`
    - `-v` shares host docker sock with deployer container -> deployer container uses context/docker process of host to compose and launch services
- localhost:3000 serves open-webui UI to query code-monkey
