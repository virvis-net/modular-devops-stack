<?php

namespace App\Support;

use PDO;

class HttpMetrics
{
    private const DURATION_BUCKETS = [
        0.005,
        0.01,
        0.025,
        0.05,
        0.1,
        0.25,
        0.5,
        1,
        2.5,
        5,
        10,
    ];

    private PDO $database;

    public function __construct(string $databasePath)
    {
        $this->database = new PDO('sqlite:'.$databasePath);
        $this->database->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        $bucketColumns = array_map(
            static fn (int $index): string => "bucket_$index INTEGER NOT NULL",
            array_keys(self::DURATION_BUCKETS)
        );

        $this->database->exec(
            'CREATE TABLE IF NOT EXISTS http_request_metrics (
                method TEXT NOT NULL,
                status INTEGER NOT NULL,
                request_count INTEGER NOT NULL,
                duration_sum REAL NOT NULL,
                '.implode(",\n                ", $bucketColumns).',
                PRIMARY KEY (method, status)
            )'
        );
        $this->database->exec(
            'CREATE TABLE IF NOT EXISTS php_runtime_metrics (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                memory_usage_bytes INTEGER NOT NULL,
                memory_peak_bytes INTEGER NOT NULL,
                gc_runs_total INTEGER NOT NULL,
                gc_collected_total INTEGER NOT NULL,
                gc_roots INTEGER NOT NULL
            )'
        );
    }

    public function observe(string $method, int $status, float $duration): void
    {
        $method = $this->normalizeMethod($method);
        $bucketCounts = array_map(
            static fn (float $boundary): int => $duration <= $boundary ? 1 : 0,
            self::DURATION_BUCKETS
        );
        $columns = array_map(
            static fn (int $index): string => "bucket_$index",
            array_keys(self::DURATION_BUCKETS)
        );
        $insertColumns = ['method', 'status', 'request_count', 'duration_sum', ...$columns];
        $updates = [
            'request_count = http_request_metrics.request_count + excluded.request_count',
            'duration_sum = http_request_metrics.duration_sum + excluded.duration_sum',
        ];
        foreach ($columns as $column) {
            $updates[] = "$column = http_request_metrics.$column + excluded.$column";
        }

        $sql = sprintf(
            'INSERT INTO http_request_metrics (%s) VALUES (%s)
             ON CONFLICT (method, status) DO UPDATE SET %s',
            implode(', ', $insertColumns),
            implode(', ', array_fill(0, count($insertColumns), '?')),
            implode(', ', $updates)
        );
        $statement = $this->database->prepare($sql);
        $statement->execute([$method, $status, 1, $duration, ...$bucketCounts]);
    }

    public function observePhpRuntime(int $memoryUsage, int $memoryPeak, array $gcStatus): void
    {
        $statement = $this->database->prepare(
            'INSERT INTO php_runtime_metrics (
                id, memory_usage_bytes, memory_peak_bytes, gc_runs_total,
                gc_collected_total, gc_roots
            ) VALUES (1, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                memory_usage_bytes = excluded.memory_usage_bytes,
                memory_peak_bytes = excluded.memory_peak_bytes,
                gc_runs_total = excluded.gc_runs_total,
                gc_collected_total = excluded.gc_collected_total,
                gc_roots = excluded.gc_roots'
        );
        $statement->execute([
            $memoryUsage,
            $memoryPeak,
            (int) ($gcStatus['runs'] ?? 0),
            (int) ($gcStatus['collected'] ?? 0),
            (int) ($gcStatus['roots'] ?? 0),
        ]);
    }

    public function render(): string
    {
        $statement = $this->database->query(
            'SELECT * FROM http_request_metrics ORDER BY method, status'
        );
        $output = "# HELP http_server_requests_total Total HTTP server requests.\n";
        $output .= "# TYPE http_server_requests_total counter\n";
        $output .= "# HELP http_server_request_duration_seconds HTTP server request duration in seconds.\n";
        $output .= "# TYPE http_server_request_duration_seconds histogram\n";

        foreach ($statement as $observation) {
            $labels = sprintf(
                'method="%s",status="%d"',
                $this->escapeLabel($observation['method']),
                $observation['status']
            );
            $output .= sprintf(
                "http_server_requests_total{%s} %d\n",
                $labels,
                $observation['request_count']
            );

            foreach (self::DURATION_BUCKETS as $index => $boundary) {
                $output .= sprintf(
                    "http_server_request_duration_seconds_bucket{%s,le=\"%s\"} %d\n",
                    $labels,
                    $this->formatNumber($boundary),
                    $observation["bucket_$index"]
                );
            }

            $output .= sprintf(
                "http_server_request_duration_seconds_bucket{%s,le=\"+Inf\"} %d\n",
                $labels,
                $observation['request_count']
            );
            $output .= sprintf(
                "http_server_request_duration_seconds_sum{%s} %s\n",
                $labels,
                $this->formatNumber((float) $observation['duration_sum'])
            );
            $output .= sprintf(
                "http_server_request_duration_seconds_count{%s} %d\n",
                $labels,
                $observation['request_count']
            );
        }

        $runtime = $this->database->query(
            'SELECT * FROM php_runtime_metrics WHERE id = 1'
        )->fetch(PDO::FETCH_ASSOC);
        $output .= "# HELP php_memory_usage_bytes PHP memory in use at the end of the last application request.\n";
        $output .= "# TYPE php_memory_usage_bytes gauge\n";
        $output .= "# HELP php_memory_peak_bytes Peak PHP memory in use during the last application request.\n";
        $output .= "# TYPE php_memory_peak_bytes gauge\n";
        $output .= "# HELP php_gc_runs_total PHP garbage collection runs since the worker started.\n";
        $output .= "# TYPE php_gc_runs_total counter\n";
        $output .= "# HELP php_gc_collected_total PHP values collected since the worker started.\n";
        $output .= "# TYPE php_gc_collected_total counter\n";
        $output .= "# HELP php_gc_roots PHP values currently buffered for garbage collection.\n";
        $output .= "# TYPE php_gc_roots gauge\n";
        if ($runtime !== false) {
            $output .= sprintf("php_memory_usage_bytes %d\n", $runtime['memory_usage_bytes']);
            $output .= sprintf("php_memory_peak_bytes %d\n", $runtime['memory_peak_bytes']);
            $output .= sprintf("php_gc_runs_total %d\n", $runtime['gc_runs_total']);
            $output .= sprintf("php_gc_collected_total %d\n", $runtime['gc_collected_total']);
            $output .= sprintf("php_gc_roots %d\n", $runtime['gc_roots']);
        }

        return $output;
    }

    public function reset(): void
    {
        $this->database->exec('DELETE FROM http_request_metrics');
        $this->database->exec('DELETE FROM php_runtime_metrics');
    }

    private function normalizeMethod(string $method): string
    {
        return in_array($method, [
            'GET',
            'HEAD',
            'POST',
            'PUT',
            'PATCH',
            'DELETE',
            'OPTIONS',
        ], true) ? $method : 'OTHER';
    }

    private function escapeLabel(string $value): string
    {
        return str_replace(
            ["\\", "\n", '"'],
            ["\\\\", "\\n", '\\"'],
            $value
        );
    }

    private function formatNumber(float $number): string
    {
        $formatted = rtrim(rtrim(sprintf('%.9F', $number), '0'), '.');

        return $formatted === '' ? '0' : $formatted;
    }
}
