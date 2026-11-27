#!/bin/sh
set -eu

python /bootstrap/deploy_gitea.py
python /bootstrap/deploy_n8n.py
