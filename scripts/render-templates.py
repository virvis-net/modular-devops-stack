#!/usr/bin/env python3
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Optional, Set
from urllib.parse import urlsplit


def required_setting(name: str, pattern=None) -> str:
    value = os.environ.get(name, "")
    if not value or "\n" in value or "\r" in value:
        raise ValueError(f"{name} must be set to a single-line value in .env")
    if pattern and not re.fullmatch(pattern, value):
        raise ValueError(f"{name} has an invalid value: {value!r}")
    return value


def optional_setting(name: str) -> str:
    value = os.environ.get(name, "")
    if "\n" in value or "\r" in value:
        raise ValueError(f"{name} must be a single-line value in .env")
    return value.strip()


def central_telemetry_settings() -> Dict[str, str]:
    ingest_enabled_value = (
        optional_setting("OTEL_CENTRAL_INGEST_ENABLED") or "false"
    ).lower()
    if ingest_enabled_value not in {"true", "false"}:
        raise ValueError("OTEL_CENTRAL_INGEST_ENABLED must be true or false")
    ingest_enabled = ingest_enabled_value == "true"
    export_mode = optional_setting("OTEL_CENTRAL_EXPORT_MODE") or "local"
    collector_endpoint = optional_setting("OTEL_CENTRAL_COLLECTOR_ENDPOINT")

    if export_mode not in {"local", "forward", "both"}:
        raise ValueError(
            "OTEL_CENTRAL_EXPORT_MODE must be one of: local, forward, both"
        )
    if export_mode in {"forward", "both"} and not collector_endpoint:
        raise ValueError(
            "OTEL_CENTRAL_COLLECTOR_ENDPOINT is required when "
            "OTEL_CENTRAL_EXPORT_MODE is forward or both"
        )
    if export_mode in {"forward", "both"} and ingest_enabled:
        raise ValueError(
            "Use OTEL_CENTRAL_INGEST_ENABLED=false on forwarding stacks; "
            "a stack cannot receive and forward with this simple configuration"
        )
    if ingest_enabled and not collector_endpoint:
        raise ValueError(
            "OTEL_CENTRAL_COLLECTOR_ENDPOINT is required when "
            "OTEL_CENTRAL_INGEST_ENABLED=true"
        )

    endpoint_host = ""
    endpoint_scheme = ""
    if collector_endpoint:
        parsed = urlsplit(collector_endpoint)
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.path not in ("", "/")
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError(
                "OTEL_CENTRAL_COLLECTOR_ENDPOINT must be an HTTP or HTTPS origin without a path"
            )
        if parsed.port is not None and not 1 <= parsed.port <= 65535:
            raise ValueError(
                "OTEL_CENTRAL_COLLECTOR_ENDPOINT has an invalid port"
            )
        endpoint_host = parsed.hostname
        endpoint_scheme = parsed.scheme
        if not re.fullmatch(
            r"(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
            r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?",
            endpoint_host,
        ):
            raise ValueError(
                "OTEL_CENTRAL_COLLECTOR_ENDPOINT must use a DNS hostname"
            )

    traces_exporters = {
        "local": "otlphttp/tempo",
        "forward": "otlphttp/central",
        "both": "otlphttp/tempo, otlphttp/central",
    }[export_mode]
    logs_exporters = {
        "local": "otlphttp/loki",
        "forward": "otlphttp/central",
        "both": "otlphttp/loki, otlphttp/central",
    }[export_mode]
    ingress_tls_block = ""
    if ingest_enabled and endpoint_scheme == "https":
        ingress_tls_block = (
            "  tls:\n"
            "    - hosts:\n"
            f"        - {endpoint_host}\n"
            "      secretName: otel-central-ingest-tls\n"
        )
    export_tls_config = ""
    if export_mode in {"forward", "both"} and endpoint_scheme == "https":
        export_tls_config = (
            "    tls:\n"
            "      ca_file: /etc/otelcol-contrib/central-auth/ca.crt\n"
        )
    return {
        "OTEL_CENTRAL_INGEST_HOST": endpoint_host,
        "OTEL_CENTRAL_INGRESS_TLS_BLOCK": ingress_tls_block,
        "OTEL_CENTRAL_EXPORT_TLS_CONFIG": export_tls_config,
        "OTEL_CENTRAL_EXPORT_MODE": export_mode,
        "OTEL_CENTRAL_INGEST_ENABLED": ingest_enabled_value,
        "OTEL_CENTRAL_COLLECTOR_ENDPOINT": collector_endpoint,
        "OTEL_CENTRAL_EXPORT_ENDPOINT": (
            collector_endpoint
            if export_mode in {"forward", "both"}
            else "http://otel-collector.monitoring.svc:4318"
        ),
        "OTEL_TRACES_EXPORTER": traces_exporters,
        "OTEL_LOGS_EXPORTER": logs_exporters,
    }


def require_renderable_git_repo(path: Path, allow_existing: bool) -> None:
    if not path.is_dir():
        raise ValueError(f"Repository clone not found: {path}")

    result = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "--is-inside-work-tree"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or result.stdout.strip() != "true":
        raise ValueError(f"Not a Git working tree: {path}")

    status = subprocess.run(
        ["git", "-C", str(path), "status", "--porcelain", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status:
        raise ValueError(
            f"{path} has uncommitted or untracked changes. Commit or stash them "
            "before rendering."
        )

    if not allow_existing:
        tracked = subprocess.run(
            ["git", "-C", str(path), "ls-files", "--cached"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        if tracked:
            raise ValueError(
                f"{path} already contains tracked files. Render an existing "
                "repository with --app-only or --gitops-only."
            )


def copy_rendered_tree(
    source: Path,
    destination: Path,
    values: Dict[str, str],
    excluded_paths: Optional[Set[Path]] = None,
) -> None:
    if excluded_paths is None:
        excluded_paths = set()
    for source_path in source.rglob("*"):
        relative = source_path.relative_to(source)
        if any(
            relative == excluded or excluded in relative.parents
            for excluded in excluded_paths
        ):
            continue
        relative = Path(
            *(values["K3D_CLUSTER_NAME"] if part == "mds-cluster" else part
              for part in relative.parts)
        )
        target = destination / relative

        if source_path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue

        content = source_path.read_text(encoding="utf-8")
        for token, value in values.items():
            content = content.replace(f"__{token}__", value)

        unresolved = re.search(
            r"__(?!(?:CLASS|DIR|FILE|FUNCTION|LINE|METHOD|NAMESPACE|TRAIT)__)"
            r"[A-Z0-9_]+__",
            content,
        )
        if unresolved:
            raise ValueError(f"Unresolved template value {unresolved.group()} in {source_path}")

        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def parse_template_options(args):
    app_template = "go"
    render_target = "both"
    app_template_set = False
    render_target_set = False
    app_templates = {"go", "laravel", "vue"}
    render_targets = {"app-only", "gitops-only"}

    for argument in args:
        if argument in app_templates:
            if app_template_set:
                raise ValueError("choose only one app template")
            app_template = argument
            app_template_set = True
        elif argument in {f"--{target}" for target in render_targets}:
            if render_target_set:
                raise ValueError("choose only one render target")
            render_target = argument[2:]
            render_target_set = True
        else:
            raise ValueError(f"unrecognized template option {argument!r}")

    return app_template, render_target


def main() -> int:
    if len(sys.argv) < 3 or len(sys.argv) > 5:
        print(
            f"Usage: {Path(sys.argv[0]).name} APP_REPO GITOPS_REPO "
            "[go|laravel|vue] [--app-only|--gitops-only]",
            file=sys.stderr,
        )
        return 2

    try:
        app_template, render_target = parse_template_options(sys.argv[3:])
    except ValueError as error:
        print(f"Template setup failed: {error}", file=sys.stderr)
        print(
            f"Usage: {Path(sys.argv[0]).name} APP_REPO GITOPS_REPO "
            "[go|laravel|vue] [--app-only|--gitops-only]",
            file=sys.stderr,
        )
        return 2

    app_templates = {
        "go": "app-go",
        "laravel": "app-laravel",
        "vue": "app-vue",
    }
    runtime_dashboards = {
        "go": "go-runtime-dashboard.json",
        "laravel": "laravel-runtime-dashboard.json",
        "vue": "vue-runtime-dashboard.json",
    }
    if app_template not in app_templates:
        print(
            f"Template setup failed: unsupported app template {app_template!r}; "
            "choose 'go', 'laravel', or 'vue'.",
            file=sys.stderr,
        )
        return 2
    render_app = render_target in {"both", "app-only"}
    render_gitops = render_target in {"both", "gitops-only"}
    root = Path(__file__).resolve().parent.parent
    app_template_root = root / "templates" / app_templates[app_template]

    try:
        values = {
            "GITEA_ORG": required_setting(
                "GITEA_ORG", r"[A-Za-z0-9][A-Za-z0-9._-]*"
            ),
        }
        if render_app:
            values["REGISTRY_PORT"] = required_setting("REGISTRY_PORT", r"\d+")
            values["GITOPS_REPO_URL"] = required_setting(
                "GITOPS_REPO_URL", r"ssh://[A-Za-z0-9@._:-]+/[A-Za-z0-9._/-]+"
            )
            if app_template == "laravel":
                values["K3D_CLUSTER_NAME"] = required_setting(
                    "K3D_CLUSTER_NAME", r"[A-Za-z0-9][A-Za-z0-9._-]*"
                )
        if render_gitops:
            runtime_overlays = app_template_root / "gitops" / "overlays"
            runtime_override_files = [
                runtime_overlays / environment / "runtime.env"
                for environment in ("staging", "production")
            ]
            has_runtime_overrides = all(
                path.is_file() for path in runtime_override_files
            )
            has_partial_runtime_overrides = any(
                path.is_file() for path in runtime_override_files
            )
            if has_partial_runtime_overrides and not has_runtime_overrides:
                raise ValueError(
                    f"{runtime_overlays} must provide runtime.env for both "
                    "staging and production"
                )
            values.update(
                {
                    "K3D_CLUSTER_PORT": required_setting(
                        "K3D_CLUSTER_PORT", r"\d+"
                    ),
                    "K3D_CLUSTER_NAME": required_setting(
                        "K3D_CLUSTER_NAME", r"[A-Za-z0-9][A-Za-z0-9._-]*"
                    ),
                    "RUNTIME_DASHBOARD": runtime_dashboards[app_template],
                    "APP_RUNTIME_CONFIG_BLOCK": (
                        "configMapGenerator:\n"
                        "  - name: app-runtime-config\n"
                        "    behavior: merge\n"
                        "    envs:\n"
                        "      - runtime.env"
                        if has_runtime_overrides
                        else ""
                    ),
                }
            )
            values.update(central_telemetry_settings())
        app_repo, gitops_repo = (Path(arg).resolve() for arg in sys.argv[1:3])
        if render_app:
            require_renderable_git_repo(
                app_repo, allow_existing=render_target == "app-only"
            )
        if render_gitops:
            require_renderable_git_repo(
                gitops_repo, allow_existing=render_target == "gitops-only"
            )

        if render_app:
            copy_rendered_tree(
                app_template_root,
                app_repo,
                values,
                excluded_paths={Path("gitops")},
            )

        if render_gitops:
            copy_rendered_tree(
                root / "templates/gitops",
                gitops_repo,
                values,
            )
            copy_rendered_tree(
                app_template_root / "gitops",
                gitops_repo / "apps/app/base/app-template",
                values,
                excluded_paths={
                    Path("cluster"),
                    Path("migration"),
                    Path("overlays"),
                },
            )
            copy_rendered_tree(
                app_template_root / "gitops/cluster",
                gitops_repo / "clusters" / values["K3D_CLUSTER_NAME"],
                values,
            )
            for environment in ("staging", "production"):
                runtime_overlay = (
                    app_template_root / "gitops" / "overlays" / environment
                )
                if runtime_overlay.is_dir():
                    copy_rendered_tree(
                        runtime_overlay,
                        gitops_repo / "apps/app/overlays" / environment,
                        values,
                    )
                copy_rendered_tree(
                    app_template_root / "gitops/migration",
                    gitops_repo
                    / "apps/app/overlays"
                    / environment
                    / "migration",
                    values,
                )
            monitoring_source = (
                root / "stack/monitoring/provider/kubernetes/manifests"
            )
            monitoring_destination = (
                gitops_repo
                / "clusters"
                / values["K3D_CLUSTER_NAME"]
                / "monitoring"
            )
            copy_rendered_tree(
                monitoring_source,
                monitoring_destination,
                values,
                excluded_paths={
                    Path("grafana/provisioning/go-runtime-dashboard.json"),
                    Path("grafana/provisioning/laravel-runtime-dashboard.json"),
                    Path("opentelemetry-collector/central-ingress"),
                }
                - {
                    Path("grafana/provisioning") / values["RUNTIME_DASHBOARD"]
                },
            )
            if values["OTEL_CENTRAL_INGEST_ENABLED"] == "true":
                copy_rendered_tree(
                    monitoring_source
                    / "opentelemetry-collector/central-ingress",
                    monitoring_destination
                    / "opentelemetry-collector/central-ingress",
                    values,
                )
                collector_kustomization = (
                    monitoring_destination
                    / "opentelemetry-collector/kustomization.yaml"
                )
                content = collector_kustomization.read_text(encoding="utf-8")
                content = content.replace(
                    "resources:\n",
                    "resources:\n  - central-ingress\n",
                    1,
                )
                collector_kustomization.write_text(content, encoding="utf-8")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Template setup failed: {error}", file=sys.stderr)
        return 1

    if render_app:
        print(f"Rendered {app_template} app template into {app_repo}")
    if render_gitops:
        print(f"Rendered GitOps template into {gitops_repo}")
        print(f"Rendered Kubernetes monitoring provider into {gitops_repo}")
    if render_gitops and values["OTEL_CENTRAL_INGEST_ENABLED"] == "true":
        print(
            "Enabled central OTLP ingestion at "
            f"{values['OTEL_CENTRAL_COLLECTOR_ENDPOINT']}"
        )
    if render_gitops and values["OTEL_CENTRAL_EXPORT_MODE"] in {"forward", "both"}:
        print(
            f"OTLP export mode {values['OTEL_CENTRAL_EXPORT_MODE']}: sending traces and logs to "
            f"{values['OTEL_CENTRAL_COLLECTOR_ENDPOINT']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
