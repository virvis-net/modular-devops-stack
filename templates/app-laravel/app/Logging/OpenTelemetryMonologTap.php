<?php

namespace App\Logging;

use Monolog\Logger;
use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Logs\Monolog\Handler;

class OpenTelemetryMonologTap
{
    public function __invoke(Logger $logger): void
    {
        $logger->pushHandler(new Handler(
            Globals::loggerProvider(),
            Logger::INFO,
            true,
        ));
    }
}
