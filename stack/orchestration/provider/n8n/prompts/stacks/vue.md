## Stack-specific rules: Vue

This is a Vue application. These rules extend the sections above.

- Section 3, step 2: if the issue concerns visible text, a page or a route, search for the full text with `git grep` under src/, covering components, views, the router and any translation files. The file that renders or declares it is the one to change. A file that only mentions it (for example a test or documentation) is not.
- Section 3, step 3: existing tests are the test files next to the components or in the tests folder (for example `*.spec.ts`). Update them in place; do not add test utilities, plugins or dependencies they do not use.
- Section 3, step 4: do not change `package.json` or the lock file unless the issue requires a new dependency. Never edit generated output such as dist/.
- Section 4: run the project's existing test script from `package.json` as one command. The runtime is not available if `node` or `npm` is missing or if node_modules does not exist; never run `npm install`.
