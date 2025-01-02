# code-monkey

consistent &amp; local llm instance deployer with automated knowledge base synchronization. State is saved between instance deployments

## Overview

- deployment of local code assistant
- runs with open-webui and ollama on top
- for Nvidia GPU support (flawless execution on gtx1080)
  - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installing-the-nvidia-container-toolkit
  - it is expected for the host to have the right drivers installed (good luck)
- to build: `$ llm-svc.sh build [-i <img tag>]`
- to run: `$ llm-svc.sh serve`
- to sync docs: `$ kb-sync --dir <project_dir> --kb-name <knowledge context uid>`
- localhost:1111 serves open-webui UI to query llms

## Todo

- automate owebui api key generation
- auto resolve perl deps
- find workaround to resync docs with diffs only && run it as a file change listener daemon
