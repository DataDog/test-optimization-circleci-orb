#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the MIT license.
# This product includes software developed at Datadog (https://www.datadoghq.com/)
# Copyright 2024-present Datadog, Inc.

if [ -z "$DD_API_KEY" ]; then
	>&2 echo "Error: DD_API_KEY environment variable not provided." && exit 1
fi

# Propagate service name and site from inputs to environment variables
if [ -n "$SERVICE" ]; then
	echo "export DD_SERVICE=$SERVICE" >> "$BASH_ENV"
fi
if [ -n "$SITE" ]; then
	echo "export DD_SITE=$SITE" >> "$BASH_ENV"
fi

echo "export DD_CIVISIBILITY_AUTO_INSTRUMENTATION_PROVIDER=circleci" >> "$BASH_ENV"

if [ -n "$PYTHON_COVERAGE_VERSION" ]; then
	>&2 echo "Warning: python_coverage_version is deprecated and has no effect: the Python tracer no longer needs the coverage package, and the orb no longer installs it."
fi

script_filepath="install_test_visibility.sh"

if command -v curl >/dev/null 2>&1; then
	curl -Lo "$script_filepath" "$INSTALLATION_SCRIPT_URL"
elif command -v wget >/dev/null 2>&1; then
	wget -O "$script_filepath" "$INSTALLATION_SCRIPT_URL"
else
	>&2 echo "Error: Neither wget nor curl is installed."
	exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  if ! echo "$INSTALLATION_SCRIPT_CHECKSUM  $script_filepath" | sha256sum -c -; then
    exit 1
  fi
elif command -v shasum >/dev/null 2>&1; then
  if ! echo "$INSTALLATION_SCRIPT_CHECKSUM  $script_filepath" | shasum -a 256 -c -; then
    exit 1
  fi
else
  >&2 echo "Error: Neither sha256sum nor shasum is installed."
  exit 1
fi

chmod +x ./install_test_visibility.sh

# Bash reads $BASH_ENV in each later step, so each value is quoted for Bash: a
# $, " or ` in it would otherwise be expanded or end the quotes. For Go, the
# installer prints ddtest's folder in front of its own PATH. Only the folders
# that this step's PATH lacks are written, in front of the PATH of the shell
# that reads $BASH_ENV: every Bash script that a later step starts reads it
# again, and a copy of the whole PATH would drop what that step put on PATH.
# The installer's Bash reads $BASH_ENV too, so its PATH can repeat folders that
# earlier steps added to $PATH, and is not this step's PATH with a prefix.
while IFS='=' read -r name value; do
  if [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    continue
  fi
  if [[ $name != PATH ]]; then
    printf 'export %s=%q\n' "$name" "$value" >> "$BASH_ENV"
    continue
  fi
  path_added=""
  path_rest="$value:"
  while [[ -n $path_rest ]]; do
    path_entry="${path_rest%%:*}"
    path_rest="${path_rest#*:}"
    if [[ -n $path_entry && ":$PATH:" != *":$path_entry:"* ]]; then
      path_added="${path_added:+$path_added:}$path_entry"
    fi
  done
  if [[ -n $path_added ]]; then
    # shellcheck disable=SC2016
    printf 'export PATH=%q:"$PATH"\n' "$path_added" >> "$BASH_ENV"
  fi
done < <(./install_test_visibility.sh)

echo "---"
echo "Installed Test Visibility libraries:"

# shellcheck source=/dev/null
source "$BASH_ENV"

if [ -n "$DD_TRACER_VERSION_DOTNET" ]; then
  echo "- __.NET:__ $DD_TRACER_VERSION_DOTNET"
fi
if [ -n "$DD_TRACER_VERSION_JAVA" ]; then
  echo "- __Java:__ $DD_TRACER_VERSION_JAVA"
fi
if [ -n "$DD_TRACER_VERSION_JS" ]; then
  echo "- __JS:__ $DD_TRACER_VERSION_JS"
fi
if [ -n "$DD_TRACER_VERSION_PYTHON" ]; then
  echo "- __Python:__ $DD_TRACER_VERSION_PYTHON"
fi
if [ -n "$DD_TRACER_VERSION_GO" ]; then
  echo "- __Go:__ $DD_TRACER_VERSION_GO"
fi
if [ -n "$DD_TRACER_VERSION_RUBY" ]; then
  echo "- __Ruby:__ $DD_TRACER_VERSION_RUBY"
fi
echo "---"
