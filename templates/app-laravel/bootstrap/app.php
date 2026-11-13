<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use App\Http\Middleware\RecordHttpMetrics;

$basePath = dirname(__FILE__, 2);

return Application::configure(basePath: $basePath)
    ->withRouting(
        web: $basePath.'/routes/web.php',
        api: $basePath.'/routes/api.php',
        commands: $basePath.'/routes/console.php',
        health: '/healthz',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->append(RecordHttpMetrics::class);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
    })
    ->create();
