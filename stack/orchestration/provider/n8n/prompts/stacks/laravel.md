## Stack-specific rules: Laravel

This is a Laravel application. These rules extend the rules above.

### Commands
- All tests: `php artisan test`
- One file or filter: `php artisan test tests/Feature/<File>.php` or `php artisan test --filter=<name>`
- Formatter: `vendor/bin/pint <files>` (only the PHP files you changed)
- Migrations: `php artisan migrate`
- Generators: `php artisan make:model <Name> --migration`, `php artisan make:controller <Name> --api`
- Dependencies: `composer require <package>`, `npm install <package>`

### Locating code
- Routes in routes/api.php are served under the /api prefix, so /api/hello is declared there as '/hello'. Add new API routes there without the /api prefix.
- For existing behaviour, search routes/ for the last path segment. The handler is the closure or controller method registered for that route.

### Generators
- Run each generator once, then run `git status --short` to see where it created files. Use the files and namespaces exactly as generated. Do not move them, do not generate a second copy, and do not hand-write a file a generator already created.
- `make:model <Name> --migration` creates the model and its migration. Do not also run `make:migration`.
- Edit the generated migration to add columns. Keep only the controller methods the issue needs.
- Controllers, routes and tests must import classes from the namespace the generator used.
- After writing a migration, run `php artisan migrate` once to check that it runs.
- Do not run migrate:fresh, migrate:reset or db:wipe. prepare.sh already reset the database to the state of main.

### Tests
- Feature tests go in tests/Feature and unit tests in tests/Unit. Follow the style of the existing tests.
- A new test that writes to the database uses the RefreshDatabase trait, unless existing tests show a different database strategy.
- Do not change phpunit.xml.

### Formatting
- Run Pint on every changed PHP file before committing. If vendor/bin/pint does not exist, follow the existing code style and do not reformat unrelated files.

### Never modify or stage
- bootstrap/cache/, storage/framework/, storage/logs/, vendor/, .env
