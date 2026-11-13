<?php

use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Session\Middleware\StartSession;
use Illuminate\Support\Facades\Route;
use Illuminate\View\Middleware\ShareErrorsFromSession;

$stateless = [
    EncryptCookies::class,
    StartSession::class,
    ShareErrorsFromSession::class,
    PreventRequestForgery::class,
];

Route::get('/', function () {
    return response()->json([
        'message' => 'Laravel API is running.',
        'endpoint' => '/api/hello',
    ]);
})->withoutMiddleware($stateless);

Route::get('/readyz', function () {
    return response('ok');
})->withoutMiddleware($stateless);
