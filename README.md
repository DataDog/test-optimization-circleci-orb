# <img height="25" src="logos/test_visibility_logo.png" /> Datadog Test Optimization CircleCI Orb

[CircleCI orb](https://circleci.com/orbs/registry/orb/datadog/test-optimization-circleci-orb) that installs and configures [Datadog Test Optimization](https://docs.datadoghq.com/tests/).
Supported languages are .NET, Java, Javascript, Python, Ruby and Go.

## About Datadog Test Optimization

[Test Optimization](https://docs.datadoghq.com/tests/) provides a test-first view into your CI health by displaying important metrics and results from your tests.
It can help you investigate and mitigate performance problems and test failures that are most relevant to your work, focusing on the code you are responsible for, rather than the pipelines which run your tests.

## Usage

1. Add the `DD_API_KEY` environment variable to your [CircleCI project settings](https://circleci.com/docs/set-environment-variable/#set-an-environment-variable-in-a-project) or [CircleCI organization's context](https://circleci.com/docs/set-environment-variable/#set-an-environment-variable-in-a-context) with the value of your [Datadog API key](https://app.datadoghq.com/organization-settings/api-keys).

2. Execute this command orb as part of your CircleCI job YAML before running the tests. Set the languages and [site](https://docs.datadoghq.com/getting_started/site/) parameters:

```yaml
version: 2.1

orbs:
  test-optimization-circleci-orb: datadog/test-optimization-circleci-orb@2

jobs:
  test:
    docker:
      - image: python:latest
    steps:
      - checkout
      - run: pip install pytest
      - test-optimization-circleci-orb/autoinstrument:
          languages: python
          site: datadoghq.com
      - run: pytest
```

### Choose an orb version

Starting with v2, each orb release pins its default library versions instead of resolving the latest versions during customer runs. [CircleCI registry orbs use semantic version references](https://circleci.com/docs/orbs/use/orb-concepts/#semantic-versioning-registry-orbs), so the value after `@` determines whether a workflow receives newer orb releases and their reviewed library snapshots:

| Reference | Example | Behavior | Trade-off |
| --------- | ------- | -------- | --------- |
| Moving major | `datadog/test-optimization-circleci-orb@2` | Receives reviewed compatible v2 releases, including library bumps. It does not move to v3. | The orb behavior and default libraries can change when a new v2 release is published. |
| Exact release | `datadog/test-optimization-circleci-orb@2.0.0` | Keeps the selected immutable production orb code and default library snapshot stable. | Requires an explicit update to receive fixes and library bumps. |

These references select the orb release and its default library snapshot. To hold one library at a specific version independently of the orb reference, [set its version parameter explicitly](#pin-an-individual-library-version).

For most workflows, `@2` is the simplest way to receive compatible, reviewed updates. Use `@2.0.0` when the orb and its defaults must remain fixed until the configuration is updated explicitly.

### Migrate from v1 to v2

The `@1` reference does not move to v2 automatically. Update the orb declaration in each CircleCI configuration you want to migrate:

```diff
- test-optimization-circleci-orb: datadog/test-optimization-circleci-orb@1
+ test-optimization-circleci-orb: datadog/test-optimization-circleci-orb@2
```

No parameter names or required configuration change. Omitted library-version parameters use the pinned v2 snapshot listed in the [configuration table](#configuration), so the first v2 run may use different libraries from the last v1 run. Those defaults no longer change independently on every run.

Explicit library-version parameters remain authoritative. With `@2`, reviewed v2 releases can update the orb and any omitted library defaults; with `@2.0.0`, the orb and its default snapshot remain fixed until the reference is updated explicitly.

Before migrating, review the v2 defaults and run a representative workflow. Set an explicit version parameter first if a workflow must keep using a validated library version.

## Configuration

The orb has the following parameters:

| Name                           | Description                                                                                                                                                                                                                                                                                         | Required | Default       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| languages                      | List of languages to be instrumented. Can be either "all" or any of "java", "js", "python", "dotnet", "ruby" (multiple languages can be specified as a space-separated list).                                                                                                                       | true     |               |
| site                           | Datadog site. See https://docs.datadoghq.com/getting_started/site for more information about sites.                                                                                                                                                                                                 | false    | datadoghq.com |
| service                        | The name of the service or library being tested.                                                                                                                                                                                                                                                    | false    |               |
| dotnet_tracer_version          | The version of Datadog .NET tracer to use.                                                                                                                                                                                                                                                         | false    | 3.50.0        |
| java_tracer_version            | The version of Datadog Java tracer to use.                                                                                                                                                                                                                                                         | false    | 1.65.1        |
| js_tracer_version              | The version of Datadog JS tracer to use.                                                                                                                                                                                                                                                           | false    | 6.12.0        |
| python_tracer_version          | The version of Datadog Python tracer to use.                                                                                                                                                                                                                                                       | false    | 4.13.1        |
| ruby_tracer_version            | The version of datadog-ci gem to use.                                                                                                                                                                                                                                                              | false    | 1.37.0        |
| go_tracer_version              | The version of Orchestrion automatic compile-time instrumentation of Go code (https://github.com/datadog/orchestrion) to use.                                                                                                                                                                      | false    | v1.12.2       |
| python_coverage_version        | The version of the Python `coverage` package to use.                                                                                                                                                                                                                                               | false    | 7.15.4        |
| java_instrumented_build_system | If provided, only the specified build systems will be instrumented (allowed values are `gradle`,`maven`,`sbt`,`ant`,`all`). `all` is a special value that instruments every Java process. If this property is not provided, all known build systems will be instrumented (Gradle, Maven, SBT, Ant). | false    |               |

### Pin an individual library version

Set a library's version parameter to override the default selected by the orb release. The explicit version remains fixed when a moving major reference advances:

```yaml
orbs:
  test-optimization-circleci-orb: datadog/test-optimization-circleci-orb@2

jobs:
  test:
    docker:
      - image: eclipse-temurin:17
    steps:
      - test-optimization-circleci-orb/autoinstrument:
          languages: java
          java_tracer_version: 1.64.0
```

This allows orb updates while holding a library at a version you have validated. The explicit parameter overrides the orb release default, remains fixed when `@2` advances, and must be updated manually to receive future fixes for that library. The same behavior applies to every library-version parameter in the table above.

Maintainers can use the local scripts described in [RELEASE.md](RELEASE.md) to create a batched library bump PR and publish the resulting orb release.

### Additional configuration

Any [additional configuration values](https://docs.datadoghq.com/tracing/trace_collection/library_config/) can be added directly to the job that runs your tests:

```yaml
jobs:
  test:
    docker:
      - image: python:latest
    steps:
      - checkout
      - run: pip install pytest
      - run: |
          echo "export DD_SERVICE=my-service" >> $BASH_ENV
          echo "export DD_ENV=staging-tests" >> $BASH_ENV
          echo "export DD_TAGS=layer:api,team:intake,key:value" >> $BASH_ENV
      - test-optimization-circleci-orb/autoinstrument:
          languages: python
          site: datadoghq.com
      - run: pytest
```

## Limitations

### Tracing vitest tests

ℹ️ This section is only relevant if you're running tests with [vitest](https://github.com/vitest-dev/vitest).

To use this script with vitest you need to modify the NODE_OPTIONS environment variable adding the `--import` flag with the value of the `DD_TRACE_ESM_IMPORT` environment variable.

```yaml
jobs:
  test:
    docker:
      - image: node:latest
    steps:
      - checkout
      - test-optimization-circleci-orb/autoinstrument:
          languages: js
          site: datadoghq.com
      - run: echo "export NODE_OPTIONS=\"$NODE_OPTIONS --import $DD_TRACE_ESM_IMPORT\"" >> $BASH_ENV
      - run: npm run test
```

**Important**: `vitest` and `dd-trace` require Node.js>=18.19 or Node.js>=20.6 to work together.

### Tracing cypress tests

To instrument your [Cypress](https://www.cypress.io/) tests with Datadog Test Optimization, please follow the manual steps in the [docs](https://docs.datadoghq.com/tests/setup/javascript/?tab=cypress).
