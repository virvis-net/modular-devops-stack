# Ollama Provider

This optional provider runs Ollama in a container named `model-host`. It is
available to services on the shared Docker network at
`http://model-host:11434` and is not published to the host. Model data is
stored in the `${STACK_NAME}-ollama-data` Docker volume. It starts only when
`OLLAMA_PROVIDER=container` is set in `.env`.

The default model is configured by `OLLAMA_MODEL` in `.env` and downloaded
the first time the containerized provider starts. The default configuration
uses native Ollama on the host instead. See the [AI Engineering guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for provider configuration.
