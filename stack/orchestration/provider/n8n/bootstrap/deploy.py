import json
import os
import time
import requests

N8N_URL = os.getenv("N8N_URL", "http://orchestration:5678")
N8N_API_KEY = os.environ["N8N_API_KEY"]

HEADERS = {
    "X-N8N-API-KEY": N8N_API_KEY,
    "Content-Type": "application/json",
}

WORKFLOW_DIR = "/assets/workflows"
DATATABLE_DIR = "/assets/datatables"


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

        except Exception:
            pass

        time.sleep(5)

    raise RuntimeError("Timed out waiting for n8n API")


def get_workflows():
    response = requests.get(
        f"{N8N_URL}/api/v1/workflows",
        headers=HEADERS,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    return response.json().get("data", [])


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


def get_datatables():
    response = requests.get(
        f"{N8N_URL}/api/v1/data-tables",
        headers=HEADERS,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    return response.json().get("data", [])


def get_datatable_by_name(name):
    for table in get_datatables():
        if table["name"] == name:
            return table

    return None


def ensure_datatable(schema_path):
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)

    table_name = schema["name"]

    existing = get_datatable_by_name(table_name)

    if existing:
        print(f"Data table exists: {table_name}")
        return existing

    response = requests.post(
        f"{N8N_URL}/api/v1/data-tables",
        headers=HEADERS,
        json=schema,
    )

    if not response.ok:
        print(response.text)

    response.raise_for_status()

    created = response.json()

    print(f"Created data table: {table_name}")

    return created


def build_datatable_mapping():
    mapping = {}

    for table in get_datatables():
        mapping[table["name"]] = table["id"]

    return mapping


def replace_datatable_references(
    obj,
    datatable_mapping,
):
    """
    Finds n8n Data Table references such as:

    {
        "__rl": true,
        "value": "old-id",
        "cachedResultName": "ai-engineering_jobs",
        "cachedResultUrl": "/projects/.../datatables/old-id"
    }

    and updates only the runtime table ID.

    We intentionally leave cachedResultUrl untouched for now,
    because it is UI metadata and may contain project-specific
    information that is not required for workflow execution.
    """

    if isinstance(obj, dict):

        if (
            obj.get("__rl") is True
            and obj.get("cachedResultName")
        ):
            table_name = obj["cachedResultName"]

            if table_name in datatable_mapping:
                obj["value"] = datatable_mapping[table_name]

        for value in obj.values():
            replace_datatable_references(
                value,
                datatable_mapping,
            )

    elif isinstance(obj, list):
        for item in obj:
            replace_datatable_references(
                item,
                datatable_mapping,
            )


def deploy_workflow(
    workflow_path,
    datatable_mapping,
):
    with open(
        workflow_path,
        "r",
        encoding="utf-8",
    ) as f:
        workflow = json.load(f)

    workflow = clean_workflow(workflow)

    replace_datatable_references(
        workflow,
        datatable_mapping,
    )

    existing = get_workflow_by_name(
        workflow["name"]
    )

    if existing:

        response = requests.put(
            f"{N8N_URL}/api/v1/workflows/{existing['id']}",
            headers=HEADERS,
            json=workflow,
        )

        if not response.ok:
            print(response.text)

        response.raise_for_status()

        print(
            f"Updated workflow: "
            f"{workflow['name']}"
        )

    else:
        response = requests.post(
            f"{N8N_URL}/api/v1/workflows",
            headers=HEADERS,
            json=workflow,
        )

        if not response.ok:
            print(response.text)

        response.raise_for_status()

        print(
            f"Created workflow: "
            f"{workflow['name']}"
        )


def deploy_datatables():
    for filename in sorted(
        os.listdir(DATATABLE_DIR)
    ):
        if not filename.endswith(
            ".schema.json"
        ):
            continue

        ensure_datatable(
            os.path.join(
                DATATABLE_DIR,
                filename,
            )
        )

    return build_datatable_mapping()


def deploy_workflows(
    datatable_mapping,
):
    for filename in sorted(
        os.listdir(WORKFLOW_DIR)
    ):
        if not filename.endswith(".json"):
            continue

        deploy_workflow(
            os.path.join(
                WORKFLOW_DIR,
                filename,
            ),
            datatable_mapping,
        )


def main():
    wait_for_n8n()

    print(
        "\n=== Deploying Data Tables ==="
    )

    datatable_mapping = deploy_datatables()

    print(
        "Resolved Data Tables:"
    )

    for name, table_id in sorted(
        datatable_mapping.items()
    ):
        print(
            f"  {name} -> {table_id}"
        )

    print(
        "\n=== Deploying Workflows ==="
    )

    deploy_workflows(
        datatable_mapping
    )

    print(
        "\nBootstrap complete"
    )


if __name__ == "__main__":
    main()
