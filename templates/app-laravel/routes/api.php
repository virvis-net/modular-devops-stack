<?php

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;

Route::get('/hello', function () {
    Log::info('Demo API request handled', ['route' => 'api/hello']);

    return response()->json([
        'message' => 'Hello from Modular DevOps Stack API!',
    ]);
});
