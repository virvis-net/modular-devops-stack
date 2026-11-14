# Ollama Provider

This provider runs Ollama as the local model host for OpenHands. The model
data is stored in the `${STACK_NAME}-ollama-data` Docker volume. Ollama is
available to services on the shared Docker network, but its API is not
published to the host.

The default model is configured by `OLLAMA_MODEL` in `.env` and downloaded
the first time the AI Engineering services start. See the [AI Engineering
guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for hardware notes and configuration.
