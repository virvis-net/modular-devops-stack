#!/usr/bin/env python3

import json
import os
import time
import requests

N8N_URL = os.getenv("N8N_URL", "http://orchestration:5678").rstrip("/")
N8N_API_KEY = os.environ["N8N_API_KEY"]

# Set to "false" to deploy workflows without activating them (development)
N8N_ACTIVATE_WORKFLOWS = (
    os.getenv("N8N_ACTIVATE_WORKFLOWS", "true").lower() == "true"
)

HEADERS = {
    "X-N8N-API-KEY": N8N_API_KEY,
    "Content-Type": "application/json",
}

WORKFLOW_DIR = "/assets/workflows"
DATATABLE_DIR = "/assets/datatables"


def api(method, path, payload=None, params=None):
    response = requests.request(
        method,
        f"{N8N_URL}{path}",
        headers=HEADERS,
        json=payload,
        params=params,
        timeout=30,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    return response.json() if response.text else None


def get_all(path):
    """Collect every item of a paginated list endpoint."""
    items = []
    cursor = None

    while True:
        page = api("GET", path, params={"cursor": cursor} if cursor else None)
        items.extend(page.get("data", []))
        cursor = page.get("nextCursor")

        if not cursor:
            return items


def load_json(path):
    # No ${VAR} expansion here, unlike the OpenHands bootstrap: workflow JSON
    # contains Code-node JavaScript with $ and ${...} that must stay untouched
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def wait_for_n8n():
    print("Waiting for n8n...")

    for _ in range(60):
        try:
            response = requests.get(
                f"{N8N_URL}/api/v1/data-tables",
                headers=HEADERS,
                timeout=5,
            )

            if response.status_code == 200:
                print("n8n API is ready")
                return

            if response.status_code in (401, 403):
                raise RuntimeError("n8n rejected the API key")

        except requests.RequestException:
            pass

        time.sleep(5)

    raise RuntimeError("Timed out waiting for n8n API")


# --- Data tables ----------------------------------------------------------


def get_datatables():
    return get_all("/api/v1/data-tables")


def get_datatable_by_name(name):
    for table in get_datatables():
        if table["name"] == name:
            return table

    return None


def ensure_datatable(schema_path):
    schema = load_json(schema_path)
    table_name = schema["name"]

    existing = get_datatable_by_name(table_name)

    if existing:
        # Existing tables are never altered: a new column in the schema file
        # does not reach an instance where the table already exists
        print(f"Data table exists: {table_name}")
        return table_name

    api("POST", "/api/v1/data-tables", schema)
    print(f"Created data table: {table_name}")

    return table_name


def build_datatable_mapping():
    return {table["name"]: table["id"] for table in get_datatables()}


def deploy_datatables():
    names = []

    for filename in sorted(os.listdir(DATATABLE_DIR)):
        if filename.endswith(".schema.json"):
            names.append(
                ensure_datatable(os.path.join(DATATABLE_DIR, filename))
            )

    return build_datatable_mapping(), names


# --- Workflows ------------------------------------------------------------


def get_workflows():
    return get_all("/api/v1/workflows")


def get_workflow_by_name(name):
    for workflow in get_workflows():
        if workflow["name"] == name:
            return workflow

    return None


def clean_workflow(workflow):
    workflow.pop("id", None)
    workflow.pop("versionId", None)
    workflow.pop("meta", None)
    workflow.pop("active", None)
    workflow.pop("tags", None)
    workflow.pop("createdAt", None)
    workflow.pop("updatedAt", None)

    return workflow


def replace_datatable_references(obj, datatable_mapping, missing):
    """
    Finds n8n Data Table references such as:

    {
        "__rl": true,
        "value": "old-id",
        "cachedResultName": "ai-engineering_jobs",
        "cachedResultUrl": "/projects/.../datatables/old-id"
    }

    and updates only the runtime table ID. cachedResultUrl is UI metadata
    and is left untouched. A data table reference whose name is not in the
    mapping is recorded in `missing`, so a typo cannot leave a stale ID.
    """

    if isinstance(obj, dict):

        if obj.get("__rl") is True and obj.get("cachedResultName"):
            table_name = obj["cachedResultName"]

            if table_name in datatable_mapping:
                obj["value"] = datatable_mapping[table_name]
            elif "datatables" in str(obj.get("cachedResultUrl", "")):
                missing.append(table_name)

        for value in obj.values():
            replace_datatable_references(value, datatable_mapping, missing)

    elif isinstance(obj, list):
        for item in obj:
            replace_datatable_references(item, datatable_mapping, missing)


def deploy_workflow(workflow_path, datatable_mapping):
    workflow = clean_workflow(load_json(workflow_path))
    name = workflow["name"]

    missing = []
    replace_datatable_references(workflow, datatable_mapping, missing)

    if missing:
        raise RuntimeError(
            f"{workflow_path}: references unknown data tables "
            f"{sorted(set(missing))}"
        )

    existing = get_workflow_by_name(name)

    if existing:
        workflow_id = existing["id"]
        api("PUT", f"/api/v1/workflows/{workflow_id}", workflow)
        print(f"Updated workflow: {name}")
    else:
        workflow_id = api("POST", "/api/v1/workflows", workflow)["id"]
        print(f"Created workflow: {name}")

    if N8N_ACTIVATE_WORKFLOWS:
        api("POST", f"/api/v1/workflows/{workflow_id}/activate")
        print(f"Activated workflow: {name}")

    return name


def deploy_workflows(datatable_mapping):
    names = []

    for filename in sorted(os.listdir(WORKFLOW_DIR)):
        if filename.endswith(".json"):
            names.append(
                deploy_workflow(
                    os.path.join(WORKFLOW_DIR, filename),
                    datatable_mapping,
                )
            )

    return names


# --- Verification ---------------------------------------------------------


def verify(table_names, workflow_names):
    problems = []

    tables = {table["name"] for table in get_datatables()}
    for name in table_names:
        if name not in tables:
            problems.append(f"data table '{name}' not found")

    workflows = {workflow["name"]: workflow for workflow in get_workflows()}
    for name in workflow_names:
        workflow = workflows.get(name)

        if workflow is None:
            problems.append(f"workflow '{name}' not found")
        # `is False`: skip the check if this n8n version omits the field
        elif N8N_ACTIVATE_WORKFLOWS and workflow.get("active") is False:
            problems.append(f"workflow '{name}' is not active")

    if problems:
        raise RuntimeError("Verification failed:\n  " + "\n  ".join(problems))

    print("All checks passed")


def main():
    wait_for_n8n()

    print("\n=== Deploying Data Tables ===")
    datatable_mapping, table_names = deploy_datatables()

    print("Resolved Data Tables:")
    for name, table_id in sorted(datatable_mapping.items()):
        print(f"  {name} -> {table_id}")

    print("\n=== Deploying Workflows ===")
    workflow_names = deploy_workflows(datatable_mapping)

    print("\n=== Verifying ===")
    verify(table_names, workflow_names)

    print("\nBootstrap complete")


if __name__ == "__main__":
    main()
