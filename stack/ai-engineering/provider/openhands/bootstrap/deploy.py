#!/usr/bin/env python3

import json
import os
import re
import time
import requests

OPENHANDS_URL = os.getenv("OPENHANDS_URL", "http://coding-agent:8000").rstrip("/")
OPENHANDS_API_KEY = os.environ["OPENHANDS_API_KEY"]

HEADERS = {
    "X-Session-API-Key": OPENHANDS_API_KEY,
    "Content-Type": "application/json",
}

PROVIDER_DIR = "/assets/provider-connections"
PROFILE_DIR = "/assets/profiles"
AGENT_PROFILE_DIR = "/assets/agent-profiles"
SETTINGS_FILE = "/assets/settings.json"
WORKSPACE_DIR = "/assets/workspaces"


def api(method, path, payload=None):
    response = requests.request(
        method,
        f"{OPENHANDS_URL}{path}",
        headers=HEADERS,
        json=payload,
        timeout=30,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    return response.json() if response.text else None


def load_json(path):
    """Load a JSON file, expanding ${VAR} from the environment (for secrets)."""
    with open(path, "r", encoding="utf-8") as f:
        text = os.path.expandvars(f.read())

    unresolved = sorted(set(re.findall(r"\$\{?\w+\}?", text)))
    if unresolved:
        raise RuntimeError(f"{path}: unresolved variables {unresolved}")

    return json.loads(text)


def wait_for_openhands():
    print("Waiting for OpenHands...")

    for _ in range(60):
        try:
            response = requests.get(
                f"{OPENHANDS_URL}/api/settings",
                headers=HEADERS,
                timeout=5,
            )

            if response.status_code == 200:
                print("OpenHands API is ready")
                return

            if response.status_code in (401, 403):
                raise RuntimeError("OpenHands rejected the access token")

        except requests.RequestException:
            pass

        time.sleep(5)

    raise RuntimeError("Timed out waiting for OpenHands API")


# --- Provider connections -------------------------------------------------


def get_provider_connections():
    return api("GET", "/api/llm/provider-connections")


def get_provider_connection_by_name(name):
    for connection in get_provider_connections():
        if connection["display_name"] == name:
            return connection

    return None


def ensure_provider_connection(path):
    desired = load_json(path)
    name = desired["display_name"]

    existing = get_provider_connection_by_name(name)

    if existing is None:
        # Identity is the display_name. A connection that was created by hand
        # under another name is not adopted, so flag likely duplicates.
        twins = [
            c["display_name"]
            for c in get_provider_connections()
            if c.get("provider") == desired.get("provider")
            and c.get("base_url") == desired.get("base_url")
        ]
        if twins:
            print(
                f"WARNING: '{name}' has the same provider and base_url as "
                f"existing connection(s) {twins}. To adopt one of them, set "
                "this file's display_name to the existing name."
            )

        api("POST", "/api/llm/provider-connections", desired)
        print(f"Created provider connection: {name}")
        return

    # The API reports only api_key_set, so a changed key is not detected here
    changed = [
        key for key in ("provider", "base_url")
        if existing.get(key) != desired.get(key)
    ]

    if changed:
        # CONFIRM this update route against your OpenAPI document
        api(
            "PATCH",
            f"/api/llm/provider-connections/{existing['id']}",
            desired,
        )
        print(f"Updated provider connection: {name} ({', '.join(changed)})")
    else:
        print(f"Provider connection exists: {name}")


def build_provider_mapping():
    return {c["display_name"]: c["id"] for c in get_provider_connections()}


def deploy_provider_connections():
    for filename in sorted(os.listdir(PROVIDER_DIR)):
        if filename.endswith(".json"):
            ensure_provider_connection(os.path.join(PROVIDER_DIR, filename))

    return build_provider_mapping()


# --- LLM profiles ---------------------------------------------------------


def resource_name(path, payload):
    """The file name without .json is the resource name, unless the file
    carries an explicit 'name' key."""
    return payload.get("name") or os.path.splitext(os.path.basename(path))[0]


def deploy_profile(path, provider_mapping):
    profile = load_json(path)
    name = resource_name(path, profile)

    # "provider" is a helper key naming a provider connection by its
    # display_name; it is not sent to the API
    provider_name = profile.pop("provider", None)

    if provider_name is None:
        raise RuntimeError(
            f"{path}: add a 'provider' key holding the display_name of a "
            f"provider connection (known: {sorted(provider_mapping)})"
        )

    if provider_name not in provider_mapping:
        raise RuntimeError(
            f"{path}: unknown provider connection '{provider_name}' "
            f"(known: {sorted(provider_mapping)})"
        )

    profile["provider_connection_id"] = provider_mapping[provider_name]
    payload = {
        "llm": profile
    }

    # Saving an existing name overwrites it; other profiles are left alone
    api("POST", f"/api/profiles/{name}", payload)
    print(f"Deployed profile: {name}")

    return name


def deploy_profiles(provider_mapping):
    names = []

    for filename in sorted(os.listdir(PROFILE_DIR)):
        if filename.endswith(".json"):
            names.append(
                deploy_profile(
                    os.path.join(PROFILE_DIR, filename),
                    provider_mapping,
                )
            )

    return names


# --- Agent profiles -------------------------------------------------------


def build_agent_profile_mapping():
    response = api("GET", "/api/agent-profiles")

    return {p["name"]: p["id"] for p in response["profiles"]}


def deploy_agent_profiles():
    for filename in sorted(os.listdir(AGENT_PROFILE_DIR)):
        if not filename.endswith(".json"):
            continue

        path = os.path.join(AGENT_PROFILE_DIR, filename)
        payload = load_json(path)
        name = resource_name(path, payload)

        # Saving an existing name overwrites it and bumps its revision
        api("POST", f"/api/agent-profiles/{name}", payload)
        print(f"Deployed agent profile: {name}")

    return build_agent_profile_mapping()


# --- Settings -------------------------------------------------------------


def apply_settings(agent_profile_mapping):
    """settings.json holds active_profile, active_agent_profile (a name) and
    optionally conversation_settings; everything but the name is sent as is."""
    if not os.path.exists(SETTINGS_FILE):
        print("No settings.json found, skipping")
        return None

    settings = load_json(SETTINGS_FILE)

    agent_profile_name = settings.pop("active_agent_profile")

    if agent_profile_name not in agent_profile_mapping:
        raise RuntimeError(
            f"Active agent profile '{agent_profile_name}' does not exist"
        )

    payload = {
        **settings,
        "active_agent_profile_id": agent_profile_mapping[agent_profile_name],
    }

    # CONFIRM that PATCH /api/settings accepts these keys in your version
    api("PATCH", "/api/settings", payload)
    print(f"Applied settings: {', '.join(sorted(payload))}")

    return payload


# --- Workspaces -----------------------------------------------------------


def get_workspaces():
    return api("GET", "/api/workspaces")["workspaces"]


def load_workspaces():
    """Each file in WORKSPACE_DIR holds one workspace object
    (id, name, path, parentPath), exactly as the API schema defines it."""
    workspaces = []

    if not os.path.isdir(WORKSPACE_DIR):
        return workspaces

    for filename in sorted(os.listdir(WORKSPACE_DIR)):
        if filename.endswith(".json"):
            workspaces.append(
                load_json(os.path.join(WORKSPACE_DIR, filename))
            )

    return workspaces


def deploy_workspaces():
    desired = load_workspaces()

    if not desired:
        print("No workspaces defined, skipping")
        return []

    listed = {workspace["path"] for workspace in get_workspaces()}
    missing = [w for w in desired if w["path"] not in listed]

    for workspace in desired:
        if workspace in missing:
            print(f"Adding workspace: {workspace['path']}")
        else:
            print(f"Workspace exists: {workspace['path']}")

    if missing:
        # One request carries all workspaces. The directories must already
        # exist in the container (volume mount + clone). The API also
        # dedupes by path, so a repeated run is harmless.
        api("POST", "/api/workspaces", {"workspaces": missing})

    return [workspace["path"] for workspace in desired]


# --- Verification ---------------------------------------------------------


def verify(applied_settings, deployed_workspaces, deployed_profiles):
    problems = []

    # Only profiles this bootstrap owns: a broken hand-made profile is not
    # a reason to fail the deployment
    for profile in api("GET", "/api/profiles")["profiles"]:
        if profile["name"] not in deployed_profiles:
            continue
        if profile.get("provider_connection_broken"):
            problems.append(
                f"LLM profile '{profile['name']}': provider connection is broken"
            )

    current = api("GET", "/api/settings")
    expected = applied_settings or {}

    for key in ("active_profile", "active_agent_profile_id"):
        if key in expected and current.get(key) != expected[key]:
            problems.append(
                f"{key}: expected {expected[key]!r}, found {current.get(key)!r}"
            )

    for key, value in expected.get("conversation_settings", {}).items():
        found = current.get("conversation_settings", {}).get(key)
        if found != value:
            problems.append(
                f"conversation_settings.{key}: expected {value!r}, found {found!r}"
            )

    listed = [w["path"] for w in get_workspaces()]
    for path in deployed_workspaces:
        if path not in listed:
            problems.append(f"workspace '{path}' is not listed")

    if problems:
        raise RuntimeError("Verification failed:\n  " + "\n  ".join(problems))

    print("All checks passed")


def main():
    wait_for_openhands()

    print("\n=== Deploying Provider Connections ===")
    provider_mapping = deploy_provider_connections()

    print("Resolved Provider Connections:")
    for name, connection_id in sorted(provider_mapping.items()):
        print(f"  {name} -> {connection_id}")

    print("\n=== Deploying LLM Profiles ===")
    deployed_profiles = deploy_profiles(provider_mapping)

    print("Resolved LLM Profiles:")
    for name in deployed_profiles:
        print(f"  {name}")

    print("\n=== Deploying Agent Profiles ===")
    agent_profile_mapping = deploy_agent_profiles()

    print("Resolved Agent Profiles:")
    for name, profile_id in sorted(agent_profile_mapping.items()):
        print(f"  {name} -> {profile_id}")

    print("\n=== Applying Settings ===")
    applied_settings = apply_settings(agent_profile_mapping)

    print("\n=== Deploying Workspaces ===")
    deployed_workspaces = deploy_workspaces()

    print("\n=== Verifying ===")
    verify(applied_settings, deployed_workspaces, deployed_profiles)

    print("\nBootstrap complete")


if __name__ == "__main__":
    main()
