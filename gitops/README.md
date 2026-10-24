# 📘 GitOps Component — Modular DevOps Stack

## Overview

The GitOps component of the Modular DevOps Stack is designed to be fully modular and provider‑agnostic.
The framework itself does not contain GitOps manifests.
Instead, it installs a GitOps engine (Flux, ArgoCD, or others), and that engine synchronizes from a dedicated external GitOps repository.

This separation ensures:

- The framework remains lightweight and neutral
- The GitOps repo remains the single source of truth
- Providers can be swapped without changing the GitOps repo
- Workloads and cluster definitions stay independent of the chosen GitOps engine
- No provider lock‑in
