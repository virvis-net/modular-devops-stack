<?php

namespace Tests\Feature;

use App\Support\HttpMetrics;
use Tests\TestCase;

class HealthTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        $this->app->make(HttpMetrics::class)->reset();
    }

    public function test_liveness_endpoint_is_healthy(): void
    {
        $this->get('/healthz')->assertOk();
    }

    public function test_readiness_endpoint_is_healthy(): void
    {
        $this->get('/readyz')->assertOk()->assertSeeText('ok');
    }

    public function test_api_returns_json(): void
    {
        $this->getJson('/api/hello')
            ->assertOk()
            ->assertExactJson([
                'message' => 'Hello from Modular DevOps Stack API!',
            ]);
    }

    public function test_prometheus_metrics_count_requests_and_exclude_health_and_scrape_routes(): void
    {
        $this->getJson('/api/hello')->assertOk();
        $this->get('/missing')->assertNotFound();
        $this->get('/healthz')->assertOk();
        $this->get('/readyz')->assertOk();

        $this->get('/metrics')->assertNotFound();

        $metrics = $this->app->make(HttpMetrics::class)->render();
        $this->assertStringContainsString('# TYPE http_server_requests_total counter', $metrics);
        $this->assertStringContainsString('# TYPE http_server_request_duration_seconds histogram', $metrics);
        $this->assertStringContainsString('http_server_requests_total{method="GET",status="200"} 1', $metrics);
        $this->assertStringContainsString('http_server_requests_total{method="GET",status="404"} 1', $metrics);
        $this->assertStringContainsString('http_server_request_duration_seconds_count{method="GET",status="200"} 1', $metrics);
    }

    public function test_prometheus_metrics_expose_php_runtime_observations(): void
    {
        $metrics = $this->app->make(HttpMetrics::class);
        $metrics->observePhpRuntime(1024, 2048, [
            'runs' => 3,
            'collected' => 12,
            'roots' => 4,
        ]);

        $output = $metrics->render();

        $this->assertStringContainsString('php_memory_usage_bytes 1024', $output);
        $this->assertStringContainsString('php_memory_peak_bytes 2048', $output);
        $this->assertStringContainsString('php_gc_runs_total 3', $output);
        $this->assertStringContainsString('php_gc_collected_total 12', $output);
        $this->assertStringContainsString('php_gc_roots 4', $output);
    }

    public function test_application_requests_record_php_runtime_metrics(): void
    {
        $this->getJson('/api/hello')->assertOk();

        $output = $this->app->make(HttpMetrics::class)->render();
        foreach ([
            'php_memory_usage_bytes',
            'php_memory_peak_bytes',
            'php_gc_runs_total',
            'php_gc_collected_total',
            'php_gc_roots',
        ] as $metric) {
            $this->assertMatchesRegularExpression('/^'.$metric.' \d+$/m', $output);
        }
    }
}
