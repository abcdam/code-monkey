#!/bin/sh
curl -fsSL https://ollama.com/install.sh | sh
rsync -hvrP /tmp/.ollama /root/

./start.sh
