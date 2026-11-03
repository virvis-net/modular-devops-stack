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
}
