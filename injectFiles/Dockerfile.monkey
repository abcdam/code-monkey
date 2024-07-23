
FROM ollama/ollama

WORKDIR /root/.ollama
COPY ./modelDefinitions/Modelfile .
RUN ollama serve & ollama_pid=$!  \
    && sleep 3  \
    && ollama create code-monkey -f ./Modelfile
RUN ollama serve & sleep 2 && ollama rm llama3.1
