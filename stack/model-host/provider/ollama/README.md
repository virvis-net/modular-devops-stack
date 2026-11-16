# Ollama Provider

This provider runs Ollama as the model-host implementation. Its Compose
service is named `model-host`, and its API is available to services on the
shared Docker network at `http://model-host:11434`; it is not published to
the host. The image adds Mesa Vulkan drivers and `vulkaninfo` to the upstream
Ollama image. Model data is stored in the `${STACK_NAME}-ollama-data` Docker
volume.

The default model is configured by `OLLAMA_MODEL` in `.env` and downloaded
the first time the AI Engineering services start. See the [AI Engineering
guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for hardware notes and configuration.

On WSL2, set `OLLAMA_WSL_VULKAN=true` to include
`docker-compose.wsl-vulkan.yaml`. That overlay passes `/dev/dxg`, WSLg's
`/dev/dri`, and `/usr/lib/wsl` into the container, and enables Ollama's
Vulkan backend. The startup script adds the numeric group IDs from the
available GPU device nodes, so it does not depend on `video` or `render`
group names being present in the Ollama image. It also selects a source-built
Mesa Dozen (DZN) Vulkan driver; the Ubuntu Mesa package does not include DZN.
The first WSL Vulkan image build compiles Mesa 25.2.8 and can take several
minutes. Keep the overlay out of non-WSL configurations because those host
paths and driver are WSL-specific.
