FROM perl:slim AS cpanm-builder
    RUN cpan App::cpanminus
    # fix shebang
    RUN sed -i '1s|^.*$|#!/usr/bin/env perl|' /usr/local/bin/cpanm
FROM ghcr.io/open-webui/open-webui:ollama 
    RUN apt-get update          \
        && apt-get install -y   \
        lshw                \
        procps              \
        lsof                \
        vim                 \
        net-tools           \
        rsync           &&  \
        rm -rf /var/lib/apt/lists/*
    COPY --from=cpanm-builder /usr/local/bin/cpanm /usr/local/bin/cpanm
    RUN  cpanm YAML::Tiny
    RUN  cpanm Const::Fast
    COPY ./assets /assets
    WORKDIR /app/backend
    RUN mv /assets/puppeteer.pl .
    RUN mv /assets/log_tee .
    CMD [ "perl", "puppeteer.pl" ]