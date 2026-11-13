<?php

namespace App\Providers;

use App\Support\HttpMetrics;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(
            HttpMetrics::class,
            static fn (): HttpMetrics => new HttpMetrics(
                storage_path('framework/cache/http-metrics.sqlite')
            )
        );
    }

    public function boot(): void
    {
    }
}
