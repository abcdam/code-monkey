FROM ghcr.io/open-webui/open-webui:ollama 

RUN apt update          \
    && apt install -y   \
    lshw                \
    rsync

COPY ./assets/models-cc.txt /tmp/
COPY ./assets/quickfix.sh .

# create config files
RUN ollama serve & sleep 0.5

# backup config files
RUN cp -r /root/.ollama /tmp/.ollama

CMD [ "bash", "quickfix.sh" ]

