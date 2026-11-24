# OpenHands Provider

This provider runs OpenHands Agent Canvas for manually invoked coding tasks.
It is kept separate from the normal stack startup so an agent never starts
automatically when the DevOps stack starts.

The Compose service joins the same external Docker network as Gitea, mounts
the app checkout at `workspace/app` and a dedicated local work area at
`/projects`, and does not mount the Docker socket or the GitOps checkout.
The launcher creates `workspace/openhands` as the invoking host user for that
work area. Browser configuration is stored under `/projects/.config`, which
is writable by the mapped user. Gitea API and Git requests use Gitea's
`scm:3000` service address;
`host.docker.internal` is available for host services such as native Ollama.
The UI is published on loopback only. See the [AI
Engineering guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for model setup, Gitea credentials, and the end-to-end workflow.

The Gitea token is available to agent processes in this container. Use a
dedicated Gitea account with access only to the app repository; agent-run
commands can read the token. Git uses an HTTP authorization header so
credentials are not embedded in the remote URL. The Compose environment
marks `workspace/app` as a safe Git directory and rewrites the host-side
localhost and configured Gitea SSH URLs to the internal HTTP endpoint, so Git
does not need an SSH client in the coding-agent container. The Compose service
runs as the host user's UID and GID, which the launcher detects automatically,
so the mounted checkout and its `.git` directory remain writable without
changing their permissions. Set `OPENHANDS_UID` and `OPENHANDS_GID` in `.env`
only if you need to override the detected IDs. A one-shot initialization
service aligns ownership of the private OpenHands state volume with those IDs;
it does not mount or change the app checkout.

OpenHands state is stored in the `${STACK_NAME}-openhands-data` Docker volume.
