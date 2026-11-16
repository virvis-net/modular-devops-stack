# OpenHands Provider

This provider runs OpenHands Agent Canvas for manually invoked coding tasks.
It is kept separate from the normal stack startup so an agent never starts
automatically when the DevOps stack starts.

The Compose service joins the same external Docker network as Gitea, mounts
only `workspace/app` at `/projects/app`, and does not mount the Docker socket
or the GitOps checkout. Gitea API and Git requests use Gitea's `scm:3000`
service address; `host.docker.internal` is available for host services such as
native Ollama. The UI is published on loopback only. See the [AI
Engineering guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for model setup, Gitea credentials, and the end-to-end workflow.

The Gitea token is available to agent processes in this container. Use a
dedicated Gitea account with access only to the app repository; agent-run
commands can read the token. Git uses an HTTP authorization header so
credentials are not embedded in the remote URL. The Compose environment
marks `/projects/app` as a safe Git directory and rewrites the host-side
localhost and configured Gitea SSH URLs to the internal HTTP endpoint, so Git
does not need an SSH client in the coding-agent container. On startup, the
launcher grants group write access to workspace files and directories owned by
the host user and adds the checkout's group to the container. It leaves files
owned by another user unchanged.

OpenHands state is stored in the `${STACK_NAME}-openhands-data` Docker volume.
