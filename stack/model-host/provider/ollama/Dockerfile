ARG OLLAMA_BASE_IMAGE=ollama/ollama:latest
FROM ${OLLAMA_BASE_IMAGE}

RUN apt-get update && \
    apt-get install -y --no-install-recommends mesa-vulkan-drivers vulkan-tools && \
    rm -rf /var/lib/apt/lists/*
