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

        return $output;
    }

    public function reset(): void
    {
        $this->database->exec('DELETE FROM http_request_metrics');
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
