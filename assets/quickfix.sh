#!/bin/sh
#curl -fsSL https://ollama.com/install.sh | sh
rsync -hvrP /tmp/.ollama /root/

ollama serve &
modelList=/tmp/models.txt

for model in $(cat "$modelList"); do
  ollama pull "$model"
done
kill -9 $(pidof ollama) # let openwebui handle the start
echo "--------------------------------------------------"
echo "--------------------------------------------------"
echo "----------------ALL-MODELS-PULLED-----------------"
echo "--------------------------------------------------"
echo "--------------------------------------------------"
./start.sh
