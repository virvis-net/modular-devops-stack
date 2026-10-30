#!/usr/bin/env python3
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict


def required_setting(name: str, pattern=None) -> str:
    value = os.environ.get(name, "")
    if not value or "\n" in value or "\r" in value:
        raise ValueError(f"{name} must be set to a single-line value in .env")
    if pattern and not re.fullmatch(pattern, value):
        raise ValueError(f"{name} has an invalid value: {value!r}")
    return value


def require_empty_git_repo(path: Path) -> None:
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

    tracked = subprocess.run(
        ["git", "-C", str(path), "ls-files", "--cached"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if tracked:
        raise ValueError(
            f"{path} already contains tracked files. Clone an empty repository."
        )

    status = subprocess.run(
        ["git", "-C", str(path), "status", "--porcelain", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status:
        raise ValueError(
            f"{path} is not empty. Clone an empty repository before copying templates."
        )


def copy_rendered_tree(source: Path, destination: Path, values: Dict[str, str]) -> None:
    for source_path in source.rglob("*"):
        relative = source_path.relative_to(source)
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

        unresolved = re.search(r"__[A-Z0-9_]+__", content)
        if unresolved:
            raise ValueError(f"Unresolved template value {unresolved.group()} in {source_path}")

        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"Usage: {Path(sys.argv[0]).name} APP_REPO GITOPS_REPO",
            file=sys.stderr,
        )
        return 2

    try:
        values = {
            "STACK_NAME": required_setting(
                "STACK_NAME", r"[A-Za-z0-9][A-Za-z0-9._-]*"
            ),
            "REGISTRY_PORT": required_setting("REGISTRY_PORT", r"\d+"),
            "K3D_CLUSTER_PORT": required_setting("K3D_CLUSTER_PORT", r"\d+"),
            "K3D_CLUSTER_NAME": required_setting(
                "K3D_CLUSTER_NAME", r"[A-Za-z0-9][A-Za-z0-9._-]*"
            ),
            "GITOPS_REPO_URL": required_setting(
                "GITOPS_REPO_URL", r"ssh://[A-Za-z0-9@._:-]+/[A-Za-z0-9._/-]+"
            ),
        }
        app_repo, gitops_repo = (Path(arg).resolve() for arg in sys.argv[1:])
        require_empty_git_repo(app_repo)
        require_empty_git_repo(gitops_repo)

        root = Path(__file__).resolve().parent.parent
        copy_rendered_tree(root / "templates/app", app_repo, values)
        copy_rendered_tree(root / "templates/gitops", gitops_repo, values)
        copy_rendered_tree(
            root / "stack/monitoring/provider/kubernetes/manifests",
            gitops_repo / "clusters" / values["K3D_CLUSTER_NAME"] / "monitoring",
            values,
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Template setup failed: {error}", file=sys.stderr)
        return 1

    print(f"Rendered app template into {app_repo}")
    print(f"Rendered GitOps template into {gitops_repo}")
    print(f"Rendered Kubernetes monitoring provider into {gitops_repo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
