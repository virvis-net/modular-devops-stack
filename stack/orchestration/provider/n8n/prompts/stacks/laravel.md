## Stack-specific rules: Laravel

This is a Laravel application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns an HTTP route, routes in routes/api.php are served under the /api prefix, so /api/hello is declared there as '/hello'. Search routes/ for the last path segment. A file that only mentions the path (for example as a JSON field) is not the handler.

- Section 3, step 3: do not add traits to tests.

- If a devcontainer is available and PHP tooling is unavailable in the workspace, attempt to use the devcontainer before concluding that the runtime is unavailable.

- When a usable devcontainer is available, treat the devcontainer as the authoritative Laravel runtime for:
  - dependency management;
  - migrations;
  - testing;
  - build verification.

- When modifying Composer dependencies:
  - update both composer.json and composer.lock;
  - generate composer.lock using Composer tooling;
  - never edit composer.lock manually;
  - do not commit dependency changes without the corresponding lockfile update.

- When modifying Node dependencies:
  - update both package.json and package-lock.json;
  - generate package-lock.json using npm tooling;
  - never edit package-lock.json manually;
  - do not commit dependency changes without the corresponding lockfile update.

- If dependencies were changed, run the appropriate dependency installation command before testing.

- When a change affects the database schema:
  - run the relevant migration commands before testing, if a runtime is available;
  - prefer existing migration conventions already used by the repository;
  - ensure affected tests continue to pass using the repository's existing database testing strategy.

- Before committing PHP changes, run the repository's existing formatting tooling if it is available.

- Prefer the formatter already used by the repository. Do not introduce a new formatter.

- When Laravel Pint is available:
  - format all modified PHP files with Pint before committing.

- If Laravel Pint is not available:
  - follow the repository's existing formatting conventions;
  - do not reformat unrelated files.

- When formatting is run inside a devcontainer, use the devcontainer PHP toolchain as the authoritative environment.

- Do not modify files under:
  - bootstrap/cache/;
  - storage/framework/;
  - storage/logs/;
  - vendor/.

- Regenerate these through tooling when required; never edit them manually.

- Section 4: run the narrowest relevant Laravel test set first. If the change affects multiple areas, run the broader relevant suite. The runtime is not available only if:
  - PHP is unavailable in the workspace; and
  - no usable devcontainer runtime is available.
