# Local Registry Provider

This folder contains the local Docker registry implementation of the registry layer.

## Components
- docker-compose.yaml — starts registry:2
- data/ — persistent storage for registry images

## Usage
docker compose up -d
curl http://localhost:5000/v2/_catalog

## Neutral Architecture
The top-level folder `registry/` represents the domain.
The `provider/` folder contains the current implementation.
This allows swapping the local registry for Harbor, GHCR, ECR, ACR, or GCR without changing the domain structure.
