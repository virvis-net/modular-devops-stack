# Local Registry Provider

This folder contains the local Docker registry implementation of the registry layer.

## Components
- docker-compose.yaml — starts registry:2
- data/ — persistent storage for registry images

## Usage

The registry is normally started by `./scripts/up.sh` on the shared Docker
network. With the default configuration, its HTTP API is available at
`http://localhost:5000`:

```sh
curl http://localhost:5000/v2/_catalog
```

The k3d nodes pull images from this registry through the mirror configured in
`stack/cluster/provider/k3d/registries.yaml`.
