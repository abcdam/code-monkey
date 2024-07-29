# code-monkey
consistent &amp; local llm instance deployer that accepts a local code repo path whose content can be vectorized and provided as context while prompting. State is saved between instance deployments

## Overview
- deployment of local code assistant
- runs with open-webui and ollama on top
- for Nvidia GPU support (flawless execution on gtx1080)
    - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installing-the-nvidia-container-toolkit
    - it is expected for the host to have the right drivers installed (good luck)
- to build: `docker build -t <image_name> .`
- to run: `./launch-code-monkey ~/dev/git/<code repo> <image_name>`
- localhost:3000 serves open-webui UI to query code-monkey
