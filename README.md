# <img height="25" src="logos/test_visibility_logo.png" /> Datadog Test Visibility CircleCI Orb

[CircleCI orb](https://circleci.com/orbs/registry/orb/datadog/test-visibility-circleci-orb) that installs and configures [Datadog Test Visibility](https://docs.datadoghq.com/tests/).
Supported languages are .NET, Java, Javascript, and Python.

## About Datadog Test Visibility

[Test Visibility](https://docs.datadoghq.com/tests/) provides a test-first view into your CI health by displaying important metrics and results from your tests.
It can help you investigate and mitigate performance problems and test failures that are most relevant to your work, focusing on the code you are responsible for, rather than the pipelines which run your tests.

## Usage

1. Add the `DD_API_KEY` environment variable to your [CircleCI project settings](https://circleci.com/docs/set-environment-variable/#set-an-environment-variable-in-a-project) or [CircleCI organization's context](https://circleci.com/docs/set-environment-variable/#set-an-environment-variable-in-a-context) with the value of your [Datadog API key](https://app.datadoghq.com/organization-settings/api-keys).

2. Execute this command orb as part of your CircleCI job YAML before running the tests. Set the languages and [site](https://docs.datadoghq.com/getting_started/site/) parameters:

```yaml
version: 2.1

orbs:
  test-visibility-circleci-orb: datadog/test-visibility-circleci-orb@1

jobs:
  test:
    docker:
      - image: python:latest
    steps:
      - checkout
      - run: pip install pytest
      - test-visibility-circleci-orb/autoinstrument:
          languages: python
          site: datadoghq.com
      - run: pytest
```

## Configuration

The orb has the following parameters:

| Name                           | Description                                                                                                                                                                                                                                                                                         | Required | Default       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| languages                      | List of languages to be instrumented. Can be either "all" or any of "java", "js", "python", "dotnet" (multiple languages can be specified as a space-separated list).                                                                                                                               | true     |               |
| site                           | Datadog site. See https://docs.datadoghq.com/getting_started/site for more information about sites.                                                                                                                                                                                                 | false    | datadoghq.com |
| service                        | The name of the service or library being tested.                                                                                                                                                                                                                                                    | false    |               |
| dotnet_tracer_version          | The version of Datadog .NET tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| java_tracer_version            | The version of Datadog Java tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| js_tracer_version              | The version of Datadog JS tracer to use. Defaults to the latest release.                                                                                                                                                                                                                            | false    |               |
| python_tracer_version          | The version of Datadog Python tracer to use. Defaults to the latest release.                                                                                                                                                                                                                        | false    |               |
| java_instrumented_build_system | If provided, only the specified build systems will be instrumented (allowed values are `gradle`,`maven`,`sbt`,`ant`,`all`). `all` is a special value that instruments every Java process. If this property is not provided, all known build systems will be instrumented (Gradle, Maven, SBT, Ant). | false    |               |

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
      - test-visibility-circleci-orb/autoinstrument:
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
      - test-visibility-circleci-orb/autoinstrument:
          languages: js
          site: datadoghq.com
      - run: echo "export NODE_OPTIONS=\"$NODE_OPTIONS --import $DD_TRACE_ESM_IMPORT\"" >> $BASH_ENV
      - run: npm run test
```

**Important**: `vitest` and `dd-trace` require Node.js>=18.19 or Node.js>=20.6 to work together.

### Tracing cypress tests

To instrument your [Cypress](https://www.cypress.io/) tests with Datadog Test Visibility, please follow the manual steps in the [docs](https://docs.datadoghq.com/tests/setup/javascript/?tab=cypress).
