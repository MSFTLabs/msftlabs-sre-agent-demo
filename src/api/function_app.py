import azure.functions as func
import logging
import time
import json
import os

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def _get_param(req: func.HttpRequest, name: str, default: str = "") -> str:
    """Read a parameter from query string first, then fall back to JSON body."""
    val = req.params.get(name)
    if val:
        return val
    try:
        body = req.get_json()
        # Support both snake_case and original key names
        if name in body:
            return str(body[name])
        snake = name.replace("-", "_")
        if snake in body:
            return str(body[snake])
    except (ValueError, AttributeError):
        pass
    return default


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "timestamp": time.time()}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-exception", methods=["POST"])
def trigger_exception(req: func.HttpRequest) -> func.HttpResponse:
    """Generates unhandled exceptions for SRE Agent to detect."""
    exception_type = _get_param(req, "type", "general")

    logging.warning("Exception trigger requested: type=%s", exception_type)

    if exception_type == "null_reference":
        obj = None
        _ = obj.some_method()  # type: ignore
    elif exception_type == "division":
        _ = 1 / 0
    elif exception_type == "timeout":
        raise TimeoutError("Simulated database connection timeout")
    elif exception_type == "memory":
        raise MemoryError("Simulated out of memory condition")
    elif exception_type == "key_error":
        d: dict = {}
        _ = d["nonexistent_key"]
    else:
        raise RuntimeError(f"Simulated unhandled error at {time.time()}")

    # Unreachable but satisfies return type
    return func.HttpResponse("", status_code=500)


@app.route(route="trigger-slow-response", methods=["POST"])
def trigger_slow_response(req: func.HttpRequest) -> func.HttpResponse:
    """Creates artificially slow responses for SRE Agent to detect."""
    delay = min(int(_get_param(req, "delay", "10") or _get_param(req, "delay_seconds", "10")), 230)

    logging.warning("Slow response triggered: %d seconds", delay)
    time.sleep(delay)

    return func.HttpResponse(
        json.dumps({"status": "completed", "delayed_seconds": delay}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-memory-leak", methods=["POST"])
def trigger_memory_leak(req: func.HttpRequest) -> func.HttpResponse:
    """Allocates memory to simulate memory pressure."""
    size_mb = min(int(_get_param(req, "size", "100") or _get_param(req, "size_mb", "100")), 500)

    logging.warning("Memory allocation triggered: %d MB", size_mb)
    # Allocate memory blocks
    _data = [bytearray(1024 * 1024) for _ in range(size_mb)]

    return func.HttpResponse(
        json.dumps({"status": "allocated", "allocated_mb": size_mb}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-cpu-spike", methods=["POST"])
def trigger_cpu_spike(req: func.HttpRequest) -> func.HttpResponse:
    """Generates CPU-intensive work for SRE Agent to detect."""
    duration = min(int(_get_param(req, "duration", "10") or _get_param(req, "duration_seconds", "10")), 60)

    logging.warning("CPU spike triggered: %d seconds", duration)
    end_time = time.time() + duration
    while time.time() < end_time:
        _ = [x**2 for x in range(10000)]

    return func.HttpResponse(
        json.dumps({"status": "completed", "cpu_spike_seconds": duration}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-dependency-failure", methods=["POST"])
def trigger_dependency_failure(req: func.HttpRequest) -> func.HttpResponse:
    """Simulates external dependency failures."""
    import urllib.request
    import urllib.error

    logging.warning("Dependency failure triggered")

    try:
        urllib.request.urlopen(
            "https://nonexistent-service-sre-demo.azurewebsites.net/api/data",
            timeout=5,
        )
    except Exception as e:
        logging.error("Dependency failure: %s", str(e))
        return func.HttpResponse(
            json.dumps({"status": "dependency_failed", "error": str(e)}),
            status_code=503,
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps({"status": "unexpected_success"}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-error-storm", methods=["POST"])
def trigger_error_storm(req: func.HttpRequest) -> func.HttpResponse:
    """Generates a burst of error log entries for SRE Agent to detect."""
    count = min(int(_get_param(req, "count", "50")), 200)

    logging.warning("Error storm triggered: %d errors", count)

    for i in range(count):
        logging.error(
            "Error storm event %d/%d: Critical failure in service component "
            "- correlation_id=storm_%d timestamp=%f",
            i + 1,
            count,
            i,
            time.time(),
        )

    return func.HttpResponse(
        json.dumps({"status": "completed", "errors_generated": count}),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="trigger-log-flood", methods=["POST"])
def trigger_log_flood(req: func.HttpRequest) -> func.HttpResponse:
    """Floods logs with high volume entries to test log analytics."""
    count = min(int(_get_param(req, "count", "1000")), 5000)
    level = _get_param(req, "level", "warning")

    log_func = getattr(logging, level, logging.warning)

    for i in range(count):
        log_func(
            "Log flood entry %d/%d: service=sre-demo component=api "
            "action=flood_test iteration=%d",
            i + 1,
            count,
            i,
        )

    return func.HttpResponse(
        json.dumps({"status": "completed", "logs_generated": count, "level": level}),
        status_code=200,
        mimetype="application/json",
    )


# ---------------------------------------------------------------------------
# SRE Demo: Managed Identity / RBAC Chaos Endpoints
# ---------------------------------------------------------------------------

KV_SECRETS_USER_ROLE = "4633458b-17de-408a-b874-0445c86b69e6"


def _get_env(name: str) -> str:
    val = os.environ.get(name, "")
    if not val:
        raise ValueError(f"Environment variable {name} is not set")
    return val


@app.route(route="revoke-keyvault-access", methods=["POST"])
def revoke_keyvault_access(req: func.HttpRequest) -> func.HttpResponse:
    """Revokes the Web App managed identity access to Key Vault secrets."""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.authorization import AuthorizationManagementClient

        sub_id = _get_env("AZURE_SUBSCRIPTION_ID")
        rg_name = _get_env("RESOURCE_GROUP_NAME")
        webapp_pid = _get_env("WEBAPP_PRINCIPAL_ID")
        kv_name = _get_env("KeyVaultName")

        credential = DefaultAzureCredential()
        auth_client = AuthorizationManagementClient(credential, sub_id)

        kv_scope = (
            f"/subscriptions/{sub_id}/resourceGroups/{rg_name}"
            f"/providers/Microsoft.KeyVault/vaults/{kv_name}"
        )

        deleted = []
        for a in auth_client.role_assignments.list_for_scope(kv_scope):
            if a.principal_id == webapp_pid and KV_SECRETS_USER_ROLE in (a.role_definition_id or ""):
                auth_client.role_assignments.delete_by_id(a.id)
                deleted.append(a.name)
                logging.warning("Revoked Key Vault role assignment %s", a.name)

        if deleted:
            logging.critical(
                "CHAOS: Web App Key Vault access REVOKED. "
                "The web app will fail to read secrets."
            )
        return func.HttpResponse(
            json.dumps({"status": "revoked" if deleted else "no_assignments_found", "deleted": deleted}),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:
        logging.error("revoke-keyvault-access failed: %s", str(e))
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


@app.route(route="restore-keyvault-access", methods=["POST"])
def restore_keyvault_access(req: func.HttpRequest) -> func.HttpResponse:
    """Restores the Web App managed identity access to Key Vault secrets."""
    try:
        import uuid
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.authorization import AuthorizationManagementClient

        sub_id = _get_env("AZURE_SUBSCRIPTION_ID")
        rg_name = _get_env("RESOURCE_GROUP_NAME")
        webapp_pid = _get_env("WEBAPP_PRINCIPAL_ID")
        kv_name = _get_env("KeyVaultName")

        credential = DefaultAzureCredential()
        auth_client = AuthorizationManagementClient(credential, sub_id)

        kv_scope = (
            f"/subscriptions/{sub_id}/resourceGroups/{rg_name}"
            f"/providers/Microsoft.KeyVault/vaults/{kv_name}"
        )
        role_def_id = (
            f"/subscriptions/{sub_id}/providers/Microsoft.Authorization"
            f"/roleDefinitions/{KV_SECRETS_USER_ROLE}"
        )

        # Check if already assigned
        for a in auth_client.role_assignments.list_for_scope(kv_scope):
            if a.principal_id == webapp_pid and KV_SECRETS_USER_ROLE in (a.role_definition_id or ""):
                return func.HttpResponse(
                    json.dumps({"status": "already_exists", "assignment": a.name}),
                    status_code=200,
                    mimetype="application/json",
                )

        assignment_name = str(uuid.uuid5(
            uuid.NAMESPACE_URL, f"{kv_scope}/{webapp_pid}/{KV_SECRETS_USER_ROLE}"
        ))
        auth_client.role_assignments.create(
            kv_scope,
            assignment_name,
            {
                "role_definition_id": role_def_id,
                "principal_id": webapp_pid,
                "principal_type": "ServicePrincipal",
            },
        )
        logging.warning("RESTORED: Web App Key Vault access restored, assignment=%s", assignment_name)
        return func.HttpResponse(
            json.dumps({"status": "restored", "assignment": assignment_name}),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:
        logging.error("restore-keyvault-access failed: %s", str(e))
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


@app.route(route="revoke-sql-access", methods=["POST"])
def revoke_sql_access(req: func.HttpRequest) -> func.HttpResponse:
    """Revokes Web App SQL connectivity by removing the Azure-services firewall rule."""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.sql import SqlManagementClient

        sub_id = _get_env("AZURE_SUBSCRIPTION_ID")
        rg_name = _get_env("RESOURCE_GROUP_NAME")
        sql_name = _get_env("SQL_SERVER_NAME")

        credential = DefaultAzureCredential()
        sql_client = SqlManagementClient(credential, sub_id)

        sql_client.firewall_rules.delete(rg_name, sql_name, "AllowAllAzureIps")
        logging.critical(
            "CHAOS: SQL Server firewall rule 'AllowAllAzureIps' DELETED. "
            "The web app will fail to connect to SQL."
        )
        return func.HttpResponse(
            json.dumps({"status": "revoked", "rule_deleted": "AllowAllAzureIps"}),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:
        logging.error("revoke-sql-access failed: %s", str(e))
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


@app.route(route="restore-sql-access", methods=["POST"])
def restore_sql_access(req: func.HttpRequest) -> func.HttpResponse:
    """Restores Web App SQL connectivity by re-creating the Azure-services firewall rule."""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.sql import SqlManagementClient

        sub_id = _get_env("AZURE_SUBSCRIPTION_ID")
        rg_name = _get_env("RESOURCE_GROUP_NAME")
        sql_name = _get_env("SQL_SERVER_NAME")

        credential = DefaultAzureCredential()
        sql_client = SqlManagementClient(credential, sub_id)

        sql_client.firewall_rules.create_or_update(
            rg_name,
            sql_name,
            "AllowAllAzureIps",
            {"start_ip_address": "0.0.0.0", "end_ip_address": "0.0.0.0"},
        )
        logging.warning(
            "RESTORED: SQL Server firewall rule 'AllowAllAzureIps' re-created."
        )
        return func.HttpResponse(
            json.dumps({"status": "restored", "rule_created": "AllowAllAzureIps"}),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:
        logging.error("restore-sql-access failed: %s", str(e))
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


@app.route(route="trigger-waf-sql-injection", methods=["POST"])
def trigger_waf_sql_injection(req: func.HttpRequest) -> func.HttpResponse:
    """Sends SQL-injection patterns to the App Gateway WAF to trigger blocking."""
    import urllib.request
    import urllib.error

    gateway_url = os.environ.get("APP_GATEWAY_URL", "")
    if not gateway_url:
        return func.HttpResponse(
            json.dumps({"error": "APP_GATEWAY_URL not configured"}),
            status_code=500,
            mimetype="application/json",
        )

    patterns = [
        "?id=1%27%20OR%20%271%27%3D%271",
        "?search=%27%3B%20DROP%20TABLE%20Users%3B--",
        "?q=1%20UNION%20SELECT%20username%2Cpassword%20FROM%20Users",
        "?input=%3Cscript%3Ealert(%27xss%27)%3C%2Fscript%3E",
        "?file=..%2F..%2Fetc%2Fpasswd",
    ]

    results = []
    for pattern in patterns:
        target = f"{gateway_url}/{pattern}"
        try:
            http_req = urllib.request.Request(target, method="GET")
            resp = urllib.request.urlopen(http_req, timeout=10)
            results.append({"pattern": pattern, "status": resp.status, "blocked": False})
        except urllib.error.HTTPError as e:
            blocked = e.code == 403
            results.append({"pattern": pattern, "status": e.code, "blocked": blocked})
            if blocked:
                logging.warning("WAF blocked request: %s (HTTP 403)", pattern)
        except Exception as e:
            results.append({"pattern": pattern, "error": str(e)})

    blocked_count = sum(1 for r in results if r.get("blocked"))
    logging.info(
        "WAF SQL injection test: %d/%d patterns blocked", blocked_count, len(patterns)
    )

    return func.HttpResponse(
        json.dumps({
            "status": "completed",
            "total_patterns": len(patterns),
            "blocked_count": blocked_count,
            "results": results,
        }),
        status_code=200,
        mimetype="application/json",
    )
