FROM ghcr.io/open-webui/open-webui:ollama 
# WORKDIR /app
WORKDIR /app

RUN apt update \
    && apt install -y \
    lshw 

COPY ./Modelfile /tmp/Modelfile

RUN ollama serve & sleep 2 \
    && ollama create code-monkey -f /tmp/Modelfile
