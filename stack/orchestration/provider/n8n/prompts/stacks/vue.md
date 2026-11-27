## Stack-specific rules: Vue

This is a Vue application. These rules extend the rules above.

### Commands
- Read the scripts section of package.json once to find the existing test, lint and format scripts. Run only scripts that exist.
- Tests: `npm test`. For one file: `npm test -- <path>`. If the test runner is Vitest, add --run so it does not start in watch mode.
- Lint or format: `npm run <script>` for the existing script, if there is one.
- If node_modules is missing, run `npm ci` once.
- Add a dependency: `npm install <package>`

### Locating code
- For visible text, a page or a route, search for the full text with `git grep` under src/, covering components, views, the router and any translation files. The file that renders or declares it is the one to change.

### Tests
- Existing tests are *.spec.ts or *.test.ts files next to the components, or files in the tests folder. Follow their style.

### Formatting
- Run the project's existing formatter or linter on changed files only if the repository already uses one. Do not introduce a new formatting or linting tool.

### Never modify or stage
- dist/, coverage/, .output/, .nuxt/, .vite/, node_modules/
