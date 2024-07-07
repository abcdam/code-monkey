FROM docker:latest

WORKDIR /usr/share/tmp

RUN apk update \
    && apk add bash \
    && apk add git \
    && git clone https://github.com/open-webui/open-webui.git

WORKDIR /usr/share/tmp/open-webui

COPY injectFiles/ .
CMD [ "docker-compose", "-f", "docker-compose.yaml", "-f", "docker-compose.gpu.yaml", "up"]