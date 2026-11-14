# OpenHands Provider

This provider runs OpenHands Agent Canvas for manually invoked coding tasks.
It is kept separate from the normal stack startup so an agent never starts
automatically when the DevOps stack starts.

The Compose service joins the shared Docker network, mounts only
`workspace/app` at `/projects/app`, and does not mount the Docker socket or
the GitOps checkout. Its UI is published on loopback only. See the [AI
Engineering guide](../../../../README.md#optional-manual-ai-engineering-proof-of-concept-phase-1)
for model setup, Gitea credentials, and the end-to-end workflow.

The Gitea token is available to agent processes in this container. Use a
dedicated Gitea account with access only to the app repository; agent-run
commands can read the token. The included Git askpass helper supplies that
account and token to HTTP Git operations without embedding credentials in the
remote URL.

OpenHands state is stored in the `${STACK_NAME}-openhands-data` Docker volume.
