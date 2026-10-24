# Flux Provider (Gitops layer)

## Overview

This folder contains the Flux provider implementation for the Modular DevOps Stack.
Flux is one of several possible GitOps engines that can be used to synchronize the cluster with the external GitOps repository.

The framework treats Flux as a pluggable provider.
It installs Flux, configures it, and connects it to the GitOps repo — but it does not contain any Flux manifests or desired‑state definitions.
Those live entirely in the external GitOps repository.

This design keeps the framework modular, provider‑agnostic, and easy to extend.
