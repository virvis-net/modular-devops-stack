# Ollama Provider

This provider runs Ollama as the model-host implementation. Its Compose
service is named `model-host`, and its API is available to services on the
shared Docker network at `http://model-host:11434`; it is not published to
the host. Model data is stored in the `${STACK_NAME}-ollama-data` Docker
volume.

The default model is configured by `OLLAMA_MODEL` in `.env` and downloaded
the first time the AI Engineering services start. See the [AI Engineering
guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for hardware notes and configuration.
