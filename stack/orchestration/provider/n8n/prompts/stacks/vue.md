## Stack-specific rules: Vue

This is a Vue application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns visible text, a page or a route, search for the full text with `git grep` under src/, covering components, views, the router and any translation files. The file that renders or declares it is the one to change. A file that only mentions it (for example a test or documentation) is not.

- Section 3, step 3: existing tests are the test files next to the components or in the tests folder (for example `*.spec.ts`). Update them in place; do not add test utilities, plugins or dependencies they do not use.

- Section 3, step 4: do not change package.json or the lock file unless the issue requires a new dependency. Never edit generated output such as dist/.

- If a devcontainer is available and Node tooling is unavailable in the workspace, attempt to use the devcontainer before concluding that the runtime is unavailable.

- When modifying dependencies:
  - update both package.json and package-lock.json;
  - generate package-lock.json using npm tooling;
  - never edit package-lock.json manually;
  - install dependencies inside the devcontainer before running tests or builds.

- Never modify files under dist/, coverage/, .output/, .nuxt/, .vite/, or other generated build output directories.

- When tests are executed inside a devcontainer, treat the devcontainer Node environment as the authoritative runtime.

- Before committing frontend source changes, run the project's existing formatter or linter only if it is already used by the repository. Do not introduce new formatting or linting tools.

- Section 4: run the project's existing test script from package.json. Use the devcontainer runtime when available. The runtime is not available only if:
  - Node tooling is unavailable in the workspace; and
  - no usable devcontainer runtime is available.
