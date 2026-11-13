<?php

return [
    'paths' => ['api/*'],
    'allowed_methods' => ['GET', 'POST', 'OPTIONS'],
    'allowed_origins' => array_values(array_filter(array_map(
        'trim',
        explode(',', env('CORS_ALLOWED_ORIGINS', '')),
    ))),
    'allowed_origins_patterns' => [],
    'allowed_headers' => [
        'Accept',
        'Content-Type',
        'Origin',
        'traceparent',
        'tracestate',
        'baggage',
    ],
    'exposed_headers' => [],
    'max_age' => 600,
    'supports_credentials' => false,
];
