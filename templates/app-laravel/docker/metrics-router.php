<?php

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

if ($path !== '/metrics') {
    http_response_code(404);
    echo "not found\n";

    return;
}

$basePath = dirname(__DIR__);

require $basePath.'/vendor/autoload.php';

$metrics = new App\Support\HttpMetrics(
    $basePath.'/storage/framework/cache/http-metrics.sqlite'
);

header('Content-Type: text/plain; version=0.0.4; charset=utf-8');
echo $metrics->render();
