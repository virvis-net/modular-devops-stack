#!/usr/bin/env python3
"""Bootstrap the Gitea labels used by the n8n AI workflow.

Same conventions as the n8n and OpenHands bootstraps: wait for the API,
apply resources by name (adopting existing ones, never deleting), verify.

Each JSON file in the labels directory may contain an array of label objects
or a single label object. Label objects use the following shape:
{
  "name": "ai/fix",                  # scoped label: scope "ai", item "fix"
  "exclusive": true,                 # only one label of the scope per issue
  "description": "...",
  "color": "#5319e7"                 # optional: kept as is on existing labels
}
"""

import json
import os
import time

import requests

GITEA_URL = os.getenv("GITEA_URL", "http://scm:3000").rstrip("/")
GITEA_API_TOKEN = os.environ["GITEA_API_TOKEN"]
GITEA_OWNER = os.environ["GITEA_OWNER"]  # the organisation (or user)

# "org": labels shared by every repository of the organisation
# "repo": labels of one repository (then GITEA_REPOSITORY is required)
LABEL_SCOPE = os.getenv("GITEA_LABEL_SCOPE", "repo")
GITEA_REPOSITORY = os.getenv("GITEA_REPOSITORY", "")

LABEL_DIR = "/assets/labels"

# Used only when a label is created and its file entry has no colour
DEFAULT_COLOR = "ededed"

HEADERS = {
    "Authorization": f"token {GITEA_API_TOKEN}",
    "Content-Type": "application/json",
}


def api(method, path, payload=None, params=None):
    response = requests.request(
        method,
        f"{GITEA_URL}{path}",
        headers=HEADERS,
        json=payload,
        params=params,
        timeout=30,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    return response.json() if response.text else None


def labels_path():
    if LABEL_SCOPE == "org":
        return f"/api/v1/orgs/{GITEA_OWNER}/labels"

    if LABEL_SCOPE == "repo" and GITEA_REPOSITORY:
        return f"/api/v1/repos/{GITEA_OWNER}/{GITEA_REPOSITORY}/labels"

    raise RuntimeError(
        "GITEA_LABEL_SCOPE must be 'org', or 'repo' together with GITEA_REPOSITORY"
    )


def get_all(path):
    """Gitea pages its lists (30 items by default), so follow the pages."""
    items = []
    page = 1

    while True:
        batch = api("GET", path, params={"page": page, "limit": 50})

        if not batch:
            return items

        items.extend(batch)
        page += 1


def normalize_color(color):
    return color.lstrip("#").lower()


def validate_labels(labels):
    """Gitea only enforces a scope for labels flagged exclusive, and the scope
    is everything before the last '/'. A half-flagged scope would silently
    not exclude anything, so reject it before touching Gitea."""
    flags_by_scope = {}

    for label in labels:
        name = label["name"]
        exclusive = bool(label.get("exclusive", False))

        if exclusive and "/" not in name:
            raise RuntimeError(
                f"label '{name}' is exclusive but has no 'scope/' prefix"
            )

        if "/" in name:
            scope = name.rsplit("/", 1)[0]
            flags_by_scope.setdefault(scope, []).append(exclusive)

    for scope, flags in flags_by_scope.items():
        if any(flags) and not all(flags):
            raise RuntimeError(
                f"scope '{scope}': either all or none of its labels "
                "must be exclusive"
            )


def load_labels():
    labels = []
    filenames = sorted(
        filename
        for filename in os.listdir(LABEL_DIR)
        if filename.endswith(".json")
    )

    if not filenames:
        raise RuntimeError(f"No label JSON files found in {LABEL_DIR}")

    for filename in filenames:
        path = os.path.join(LABEL_DIR, filename)
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        if isinstance(data, dict):
            data = [data]

        if not isinstance(data, list):
            raise RuntimeError(
                f"{path}: expected a JSON array or a single label object"
            )

        labels.extend(data)

    validate_labels(labels)

    return labels


def wait_for_gitea():
    print("Waiting for Gitea...")

    for _ in range(60):
        try:
            # Also proves that the token is valid
            response = requests.get(
                f"{GITEA_URL}/api/v1/orgs",
                headers=HEADERS,
                timeout=5,
            )

            if response.status_code == 200:
                print("Gitea API is ready")
                return

            if response.status_code in (401, 403):
                raise RuntimeError("Gitea rejected the bootstrap token")

        except requests.RequestException:
            pass

        time.sleep(5)

    raise RuntimeError("Timed out waiting for Gitea API")


def ensure_label(desired, existing):
    name = desired["name"]
    color = normalize_color(desired["color"]) if desired.get("color") else None
    description = desired.get("description", "")
    exclusive = bool(desired.get("exclusive", False))

    current = existing.get(name)

    if current is None:
        api(
            "POST",
            labels_path(),
            {
                "name": name,
                "color": f"#{color or DEFAULT_COLOR}",
                "description": description,
                "exclusive": exclusive,
            },
        )
        print(f"Created label: {name}")
        return

    changes = {}

    # No colour in the file: keep whatever the existing label has
    if color and normalize_color(current.get("color", "")) != color:
        changes["color"] = f"#{color}"

    if current.get("description", "") != description:
        changes["description"] = description

    if bool(current.get("exclusive")) != exclusive:
        changes["exclusive"] = exclusive

    # An archived label cannot be applied to issues
    if current.get("is_archived"):
        changes["is_archived"] = False

    if changes:
        api("PATCH", f"{labels_path()}/{current['id']}", changes)
        print(f"Updated label: {name} ({', '.join(sorted(changes))})")
    else:
        print(f"Label exists: {name}")


def verify(desired_labels):
    current = {label["name"]: label for label in get_all(labels_path())}
    problems = []

    for desired in desired_labels:
        name = desired["name"]
        label = current.get(name)

        if label is None:
            problems.append(f"label '{name}' not found")
            continue

        if label.get("is_archived"):
            problems.append(f"label '{name}' is archived")

        if bool(label.get("exclusive")) != bool(desired.get("exclusive", False)):
            problems.append(
                f"label '{name}': exclusive is {bool(label.get('exclusive'))}, "
                f"expected {bool(desired.get('exclusive', False))}"
            )

    if problems:
        raise RuntimeError("Verification failed:\n  " + "\n  ".join(problems))

    print("Resolved Labels:")
    for desired in desired_labels:
        print(f"  {desired['name']} -> {current[desired['name']]['id']}")

    print("All checks passed")


def main():
    wait_for_gitea()

    desired_labels = load_labels()

    print(f"\n=== Deploying Labels ({LABEL_SCOPE}: {GITEA_OWNER}) ===")
    existing = {label["name"]: label for label in get_all(labels_path())}

    for desired in desired_labels:
        ensure_label(desired, existing)

    print("\n=== Verifying ===")
    verify(desired_labels)

    print("\nBootstrap complete")


if __name__ == "__main__":
    main()
