FROM ghcr.io/open-webui/open-webui:ollama 

RUN apt update          \
    && apt install -y   \
    lshw                \
    rsync           &&  \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /assets

COPY ./assets/models.yaml /assets/
COPY ./assets/runtime-prepper.py /assets/
#COPY ./configs/authority/local-ca.crt
#RUN update-ca-certificates
RUN ollama serve & sleep 0.5
RUN cp -r /root/.ollama /assets/.ollama
CMD [ "python", "/assets/runtime-prepper.py" ]

