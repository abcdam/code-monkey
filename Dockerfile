FROM ghcr.io/open-webui/open-webui:ollama 

RUN apt update          \
    && apt install -y   \
    lshw                \
    rsync

COPY ./assets/models.yaml /tmp/
COPY ./assets/runtime-prepper.py .

# create config files
RUN ollama serve & sleep 0.5

# backup config files because original path will be mounted from host
RUN cp -r /root/.ollama /tmp/.ollama

CMD [ "python", "runtime-prepper.py" ]

