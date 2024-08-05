FROM ghcr.io/open-webui/open-webui:ollama 

RUN apt update          \
    && apt install -y   \
    lshw                \
    rsync

# RUN mkdir -p /tmp/data/external-models
# COPY ./shared-dir/external-models/* /tmp/data/external-models/

COPY ./Modelfile /tmp/Modelfile

RUN ollama serve & sleep 2                          \
    && ollama create code-monkey -f /tmp/Modelfile  \
    && ollama pull mxbai-embed-large:latest         \
    && cp -r /root/.ollama /tmp/.ollama

COPY ./quickfix.sh .

ENV WEBUI_AUTH=false                                
ENV USE_CUDA_DOCKER=true                            
ENV RAG_TOP_K=10                                    
ENV RAG_EMBEDDING_ENGINE=ollama                     
ENV RAG_EMBEDDING_MODEL=mxbai-embed-large:latest    
ENV CHUNK_SIZE=1024                                 
ENV CHUNK_OVERLAP=220

CMD [ "bash", "quickfix.sh" ]

