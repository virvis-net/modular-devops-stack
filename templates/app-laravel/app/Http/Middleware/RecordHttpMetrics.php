<?php

namespace App\Http\Middleware;

use App\Support\HttpMetrics;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

class RecordHttpMetrics
{
    public function __construct(private HttpMetrics $metrics)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        if ($request->is('healthz', 'readyz', 'metrics')) {
            return $next($request);
        }

        memory_reset_peak_usage();
        $start = hrtime(true);
        $status = Response::HTTP_INTERNAL_SERVER_ERROR;

        try {
            $response = $next($request);
            $status = $response->getStatusCode();

            return $response;
        } catch (Throwable $exception) {
            $status = $exception instanceof HttpExceptionInterface
                ? $exception->getStatusCode()
                : Response::HTTP_INTERNAL_SERVER_ERROR;

            throw $exception;
        } finally {
            $this->metrics->observe(
                $request->method(),
                $status,
                (hrtime(true) - $start) / 1_000_000_000
            );
            $this->metrics->observePhpRuntime(
                memory_get_usage(true),
                memory_get_peak_usage(true),
                gc_status()
            );
        }
    }
}
