FROM python:3.12-alpine

RUN pip install --no-cache-dir requests

WORKDIR /bootstrap

COPY deploy_n8n.py deploy_gitea.py run.sh ./

CMD ["sh", "/bootstrap/run.sh"]
