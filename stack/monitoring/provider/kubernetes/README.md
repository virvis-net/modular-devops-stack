# Kubernetes monitoring provider

This provider owns the Kubernetes deployment configuration for Prometheus and
Grafana. Its manifests are rendered by `scripts/copy-templates.sh` into the
GitOps repository at `clusters/<K3D_CLUSTER_NAME>/monitoring/`. The cluster
Kustomization includes that directory, and Flux applies the rendered resources.

The provider deploys Prometheus, Grafana, kube-state-metrics, an
OpenTelemetry Collector, Loki, and Tempo as separate workloads in the
`monitoring` namespace. It also deploys a Kubernetes event exporter,
Alertmanager, and Mailpit as a local email sink.
Prometheus discovers app metrics endpoints in staging and production,
Kubernetes state from a least-privilege kube-state-metrics deployment,
ingress-nginx metrics, and kubelet resource metrics. App metrics include HTTP
request counts and durations. Grafana queries Prometheus through its in-cluster
Service and is exposed at
`http://monitoring.localhost:<K3D_CLUSTER_PORT>/` through ingress-nginx. Its
anonymous viewer access allows dashboard viewing without signing in; Grafana
Explore requires a login. Keep both uses within the trusted local lab.

Grafana provisions a technology-agnostic application and infrastructure
dashboard and the runtime dashboard matching the app template selected during
setup. The Go dashboard shows goroutines, heap and stack memory, and garbage-
collection cycles. The Laravel/PHP dashboard shows memory observed at the end
of the last application request and PHP garbage-collection activity. These
per-request runtime observations are specific to the local PHP built-in server
used by the Laravel example and should be revisited if its application server
or worker model changes.

Prometheus also scrapes kubelet resource metrics through the Kubernetes API
server's node proxy. The Prometheus service account can discover nodes and
`get` the `nodes/proxy` subresource; this permission is required for the proxy
path and should be considered when adapting the setup beyond this trusted
local lab.

The dashboard adds pod phases, desired versus available app replicas,
container restarts, configured CPU and memory requests, live node CPU and
memory working set, staging/production container CPU and memory working set,
and ingress request rate, status, and p95 latency. Resource requests show
configured capacity; kubelet resource metrics show observed usage.

The Collector accepts OTLP over gRPC and HTTP on internal ClusterIP Service
ports 4317 and 4318. It exports traces to Tempo, logs to Loki, and metrics to
its Prometheus exporter, which Prometheus scrapes. Tempo's metrics generator
also remote-writes span and service-graph metrics to Prometheus.
The Collector adds `k8s.cluster.name` to traces and OTLP logs when the source
has not already set it, so a central trace view can distinguish otherwise
similarly named services across stacks. Give each stack a unique
`K3D_CLUSTER_NAME`.

Grafana provisions Prometheus, Loki, and Tempo data sources. Use Grafana
Explore with Loki and the query `{service_name="app"} | trace_id != ""`
to find correlated app request logs; the `TraceID` link opens the trace in
Tempo. Tempo's trace-to-logs link filters Loki by service and trace ID, and
Prometheus exemplars link applicable metric samples back to Tempo. The
dashboard includes the OTel HTTP request-duration p95 panel.

### Central traces from multiple stacks

Every stack keeps its own in-cluster Collector. A receiving stack can expose
its OTLP/HTTP receiver through an authenticated ingress; a second stack's
Collector sends traces and OTLP logs to it. The receiving Collector stores
them in its local Tempo and Loki, so that stack's Grafana can open the complete
trace and follow the existing trace-to-logs links.

`OTEL_CENTRAL_EXPORT_MODE` controls where each stack sends its own traces and
OTLP logs:

- `local` (default) sends only to that stack's Tempo and Loki.
- `forward` sends only to the central Collector; the forwarding stack does not
  keep a local copy of traces or OTLP logs.
- `both` sends to both the local backends and the central Collector.

For multiple k3d stacks on one Docker host, use the k3d-provided
`host.k3d.internal` name. k3d adds it to cluster DNS so pods can reach the host;
the host port mapping then directs traffic to the selected cluster's load
balancer. The central stack's host ports can use the defaults or any available
ports. Every stack's host ports must be unique. Each forwarder must target the
central stack's actual mapped port:

| Stack | HTTP port | HTTPS port | Gitea HTTP / SSH | Woodpecker | Registry |
|---|---:|---:|---:|---:|---:|
| Central | 80 | 443 | 3000 / 2222 | 8000 | 5000 |
| Source 1 | 8081 | 8444 | 3100 / 2223 | 8001 | 5001 |
| Source 2 | 8082 | 8445 | 3200 / 2224 | 8002 | 5002 |

For example, the central stack could instead use HTTP 9080 and HTTPS 9443;
update the endpoint on the receiver and every forwarder to
`https://host.k3d.internal:9443`. The source stacks still use their own unique
ports for their browser ingress.

Give each checkout a unique `STACK_NAME`; this also gives it a separate Docker
network and storage volumes. Set the ports in each checkout's `.env`. The
source stacks' own ingress ports do not change the central endpoint; it always
targets the central stack's mapped port. Do not use
`${K3D_CLUSTER_PORT_SSL}` in a forwarder's endpoint: it expands to that
forwarder's port, not the central stack's port.

The `.env` configuration uses three variables. On the receiving stack, enable
ingest, leave export local, and use the default endpoint:

```dotenv
OTEL_CENTRAL_INGEST_ENABLED=true
OTEL_CENTRAL_EXPORT_MODE=local
OTEL_CENTRAL_COLLECTOR_ENDPOINT=https://host.k3d.internal:443
```

On each forwarding stack, use the same endpoint and choose `forward` or `both`:

```dotenv
OTEL_CENTRAL_INGEST_ENABLED=false
OTEL_CENTRAL_EXPORT_MODE=forward
OTEL_CENTRAL_COLLECTOR_ENDPOINT=https://host.k3d.internal:443
```

For a local copy as well as the central copy, use
`OTEL_CENTRAL_EXPORT_MODE=both`. The endpoint is required for `forward` and
`both`. On a receiver in `local` mode, it identifies the ingress hostname. The
default endpoint is unused when export is `local` and ingestion is disabled.
Avoid configuring routes that point back to the same stack or create cycles.

Do not use `*.localhost` for Collector traffic: those names resolve to the
caller itself. The existing `monitoring.localhost` and app `*.localhost` URLs
are for browsers on the host. For stacks on different machines, replace
`host.k3d.internal` and the port with a DNS name and port reachable from the
source Collector.

An optional CIDR allowlist is separate from Kubernetes node identity: it filters
the source addresses ingress-nginx sees. It can help restrict access when
forwarding stacks have stable egress IPs, but NAT may make the observed address
a gateway rather than a node. It is optional and is not another `.env` variable.
To add it, put an ingress-nginx
`whitelist-source-range` annotation on the generated central-ingest Ingress,
for example `198.51.100.42/32,2001:db8:abcd::/48` (documentation-only ranges).

### Secret and TLS setup

The endpoint scheme controls TLS. HTTPS is the default and creates a TLS
ingress; HTTP omits TLS. Both modes use Basic Auth, and the Kubernetes Secret
names are fixed in the manifests. For the commands below, replace the context
names with the contexts for your stacks (`k3d-<K3D_CLUSTER_NAME>`):

```sh
API_CONTEXT=k3d-api-cluster
FRONTEND_CONTEXT=k3d-frontend-cluster
```

Install `mkcert` and `htpasswd` first (`apache2-utils` on Debian/Ubuntu or
`httpd-tools` on Fedora/RHEL). Run the API stack and wait for Flux to create
its `monitoring` namespace. For local HTTPS, create a certificate for the
ingress hostname and a local CA:

```sh
mkcert -install
mkcert host.k3d.internal
```

The commands create `host.k3d.internal.pem` and
`host.k3d.internal-key.pem`. On the API context, create the TLS Secret and the
ingress-nginx Basic Auth Secret:

```sh
kubectl --context "$API_CONTEXT" create secret tls otel-central-ingest-tls \
  --namespace monitoring \
  --cert=host.k3d.internal.pem --key=host.k3d.internal-key.pem

htpasswd -c auth otel-forwarder
kubectl --context "$API_CONTEXT" create secret generic otel-central-ingest-auth \
  --namespace monitoring --from-file=auth=./auth
```

Use a certificate whose SAN covers the hostname in
`OTEL_CENTRAL_COLLECTOR_ENDPOINT`. Each forwarder also needs the issuing CA,
because the Collector pod does not inherit the host's `mkcert -install` trust.
Create a Basic Auth client Secret in the frontend context. Use the same
password entered for `htpasswd`:

```sh
read -rsp 'Basic Auth password: ' OTEL_INGEST_PASSWORD
printf '\n'
OTEL_AUTH_HEADER="Basic $(printf '%s' "otel-forwarder:${OTEL_INGEST_PASSWORD}" | base64 | tr -d '\n')"
kubectl --context "$FRONTEND_CONTEXT" create secret generic otel-central-client-auth \
  --namespace monitoring \
  --from-literal=authorization="${OTEL_AUTH_HEADER}" \
  --from-file=ca.crt="$(mkcert -CAROOT)/rootCA.pem"
unset OTEL_INGEST_PASSWORD OTEL_AUTH_HEADER
```

Repeat the client Secret command for each forwarding stack, using its context.
Never commit the password, Basic Auth header, private key, or Secret data to
Git. The CA certificate is public but should still be kept with the local
configuration that needs it.

For HTTP, skip `mkcert` and the receiver TLS Secret. Set the endpoint on the
API stack and its forwarders to `http://host.k3d.internal:<CENTRAL_HTTP_PORT>`;
for the default central port, that is `http://host.k3d.internal:80`. Create
each client Secret with only the `authorization` key, omitting `--from-file`.
HTTP sends the Basic Auth header and telemetry without encryption, so use it
only on a trusted single-host lab and do not expose the port to an untrusted
network. The Collector appends `/v1/traces` and `/v1/logs` to the endpoint.

After Flux reconciles both GitOps repositories, send a request that crosses
stacks. In the receiving stack's Grafana, use Tempo Explore to open the trace.
The trace-to-logs link queries the receiving stack's Loki, which now contains
OTLP logs forwarded from both stacks. The reverse TraceID link from Loki is
also provisioned. Laravel app-template workloads export correlated Monolog
records over OTLP; other services need to emit OTLP logs containing trace IDs
for log correlation to resolve.

With the default `local` mode and ingest disabled, the Collector continues
exporting to its local Tempo and Loki and the stack does not expose an OTLP
ingress. HTTPS is recommended. HTTP is convenient for a trusted local lab, but
Basic Auth and telemetry are readable on the network. Restrict host ports where
practical and rotate Basic Auth credentials. Add stronger ingress controls or
mTLS before using it outside the lab. Central Tempo and Loki still use this
stack's local single-replica storage and retention settings.

These values are render-time settings. `copy-templates.sh` renders only into
empty repositories; for an already deployed stack, make the equivalent changes
in its GitOps repository and let Flux reconcile them.

<a id="cross-stack-frontend-backend-exercise"></a>

### Step-by-step frontend/backend exercise

This exercise runs a Go frontend/BFF in one stack and the Laravel API in a
second stack. The API stack receives telemetry from both Collectors and its
Grafana shows the combined trace. The Go template currently serves a static
response; the small code change below makes it call the Laravel API so the
request crosses the stack boundary.

1. **Choose stack names and ports.** Use two separate checkouts of this
   repository, for example `frontend` and `api`, and give each a unique
   `STACK_NAME`. Start with the central/API stack's default HTTP/HTTPS ports
   `80` and `443`, and use unused ports such as `8081` and `8444` for the
   frontend stack. If those central ports are occupied, choose any available
   pair, such as `9080` and `9443`. Ports must be unique on the Docker host;
   the API endpoint below must use the API stack's actual HTTP port.

2. **Configure the API stack as the receiver.** In the API checkout's `.env`,
   set:

   ```dotenv
   OTEL_CENTRAL_INGEST_ENABLED=true
   OTEL_CENTRAL_EXPORT_MODE=local
   OTEL_CENTRAL_COLLECTOR_ENDPOINT=https://host.k3d.internal:443
   ```

   Replace `443` with the API stack's HTTPS host port if you chose another
   value. For example, use `https://host.k3d.internal:9443` when the API
   stack maps HTTPS to `9443`. This endpoint also sets the host covered by the
   receiver Ingress and TLS certificate.

3. **Configure the frontend stack as a forwarder.** In the frontend
   checkout's `.env`, set:

   ```dotenv
   OTEL_CENTRAL_INGEST_ENABLED=false
   OTEL_CENTRAL_EXPORT_MODE=forward
   OTEL_CENTRAL_COLLECTOR_ENDPOINT=https://host.k3d.internal:443
   ```

   Use exactly the same central endpoint as in the API checkout. Set
   `OTEL_CENTRAL_EXPORT_MODE=both` if you also want the frontend stack to keep
   a local telemetry copy. The endpoint port is the API stack's HTTPS port,
   not the frontend stack's HTTPS port.

4. **Initialize both stacks and render the apps.** In the API checkout, run
   `./scripts/copy-templates.sh laravel`; in the frontend checkout, run
   `./scripts/copy-templates.sh go`. Follow the root README installation
   steps and each generated app README to set up the two GitOps repositories
   and start both clusters. Wait for Flux to create each stack's `monitoring`
   namespace before making its Secrets.

5. **Create the receiver and client Secrets.** On the API stack, create
   `otel-central-ingest-tls` and `otel-central-ingest-auth`; on the frontend
   stack, create `otel-central-client-auth`. Follow the HTTPS commands in
   [Secret and TLS setup](#secret-and-tls-setup) above. Substitute the actual
   Kubernetes contexts. The API Secret belongs to the receiving stack; create
   a client Secret in every forwarding stack.

6. **Set distinct service names and deploy the apps.** In the API GitOps
   repository, set the staging app's `OTEL_SERVICE_NAME` to `backend`; in the
   frontend GitOps repository, set it to `frontend`. These values are in
   `apps/app/base/deployment.yaml`. Add this environment variable to that
   same Deployment in the frontend GitOps repository, using the API's actual
   HTTP host port:

   ```yaml
   - name: BACKEND_URL
     value: http://host.k3d.internal:80/api/hello
   ```

   The distinct service names make the trace and logs easier to read. Commit
   and push the GitOps changes and follow the generated app READMEs to publish
   each app so Flux deploys them.

7. **Make the frontend call the API with tracing enabled.** In
   `src/main.go` in the frontend app repository, replace `homeHandler` with
   a handler that uses an instrumented HTTP transport. For example:

   ```go
   func homeHandler(w http.ResponseWriter, r *http.Request) {
       backendURL := os.Getenv("BACKEND_URL")
       req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, backendURL, nil)
       if err != nil {
           http.Error(w, "cannot create backend request", http.StatusInternalServerError)
           return
       }
       // The central API ingress routes by this host name.
       req.Host = "staging.localhost"

       client := &http.Client{
           Transport: otelhttp.NewTransport(http.DefaultTransport),
           Timeout:   10 * time.Second,
       }
       resp, err := client.Do(req)
       if err != nil {
           http.Error(w, "backend request failed", http.StatusBadGateway)
           return
       }
       defer resp.Body.Close()
       w.Header().Set("Content-Type", "application/json")
       w.WriteHeader(resp.StatusCode)
       _, _ = io.Copy(w, resp.Body)
   }
   ```

   Add `io` to the imports. `otelhttp.NewTransport` creates the client span
   and injects W3C trace context; Laravel's request instrumentation extracts
   it on the API side. Set `BACKEND_URL` on the frontend Deployment to
   `http://host.k3d.internal:80/api/hello` when the API stack uses HTTP port
   80, or substitute its actual HTTP host port (for example,
   `http://host.k3d.internal:9080/api/hello`). The `req.Host` override lets
   central ingress route the request to `staging.localhost`. Commit and push
   this change to the frontend app repository so CI builds and deploys it.

8. **Generate and inspect a cross-stack trace.** Open the frontend at
   `http://staging.localhost:<FRONTEND_HTTP_PORT>/` and make a request. In the
   API stack, open Grafana at
   `http://monitoring.localhost:<API_HTTP_PORT>/`, select Tempo in Explore,
   and open a recent trace. It should contain the frontend server span, the
   frontend HTTP client span, and the Laravel backend server span. Follow the
   trace-to-logs link to see correlated OTLP logs from either stack in the
   API stack's Loki.

This server-side frontend/BFF exercise traces the browser request as it
reaches the Go server and follows its API call. It does not capture browser
JavaScript execution or page rendering. For browser-side spans, add the
OpenTelemetry JavaScript SDK and configure browser CORS and an OTLP endpoint;
never put the Collector's Basic Auth credential in browser code. A browser
SDK needs a separately secured ingest path because the lab's central receiver
uses Basic Auth.

Loki retains logs for seven days and Tempo retains traces for 48 hours. Each
uses a 2Gi PVC, backed by the cluster's local-path storage in the local k3d
setup. These are single-replica local backends, not highly available; PVCs
provide persistence across pod restarts but are not backups.

The event exporter has read-only access to Kubernetes Events and pushes them
to Loki with the `job="kubernetes-events"` label. Query them in Grafana Explore
with `{job="kubernetes-events"}`. The event exporter uses a 60-second event
age cutoff, so it collects current events rather than serving as a durable
Kubernetes event archive.

Prometheus evaluates alerts for scrape targets that stay down, an elevated
application 5xx rate, pod image-pull failures, and crash-looping containers.
Alertmanager routes firing and resolved notifications to a local Mailpit SMTP
inbox; no external notification service is configured. To inspect alerts and
the test inbox, open `http://notifications.localhost:<K3D_CLUSTER_PORT>/` in
your browser. The neutral `notifications.localhost` host routes only the
Mailpit web UI; SMTP remains internal to the cluster. The inbox has no
authentication, so keep it within the trusted local lab. Prometheus remains
internal and is available for rule inspection with a port-forward:

```bash
kubectl port-forward -n monitoring service/prometheus 9090:9090
```

Open `http://localhost:9090/alerts` to see evaluated alert rules and
`http://notifications.localhost:<K3D_CLUSTER_PORT>/` to inspect email
notifications. A clean install may leave firing and resolved notifications
for transient startup alerts in the inbox. To exercise event collection and
the image-pull alert again, create a temporary pod using a deliberately
invalid image:

```bash
kubectl run observability-alert-test -n staging \
  --image=example.invalid/observability-alert-test:missing --restart=Never
```

Wait at least two minutes for `KubernetesPodImagePullBackOff` to fire. Query
Loki with `{job="kubernetes-events"} |= "observability-alert-test"` and check
the alert in Prometheus and its email in Mailpit. Then remove the test pod:

```bash
kubectl delete pod observability-alert-test -n staging
```

Alertmanager and Mailpit are for this trusted local lab only. Mailpit is
in-memory, receives no external mail, and loses messages when restarted.

The ingress controller's metrics endpoint is enabled by
`stack/ingress/provider/nginx/enable-metrics.sh`; the provider includes a
separate internal Service for scraping it. Prometheus scrape configuration is
generated from `prometheus/config/prometheus.yml`, so changing scrape jobs
updates its ConfigMap hash and rolls out Prometheus automatically.

Grafana provisioning files are managed with Kustomize's ConfigMap generator.
Their content hash is included in the generated ConfigMap name and referenced
by the Deployment, so changing a dashboard or provisioning file changes the
pod template and automatically rolls out Grafana when Flux reconciles. No
manual pod restart or external reloader is required.

Monitoring is included by the current template-rendering workflow. Provider
selection and alternative implementations are intentionally deferred until
provider configuration is generalized across the stack.
