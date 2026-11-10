#!/usr/bin/env bash
# The CI's Go checks around the orb's autoinstrument command, in two steps of
# one job, as users run them:
#
#   tests/go-check.sh prepare root|multiple_modules
#       before the orb: writes Go modules that declare go 1.22 into
#       /tmp/go-check/project, records the toolchain's go, and writes to
#       $BASH_ENV a folder in front of PATH and one behind it, as earlier
#       steps often do;
#   tests/go-check.sh check instrumented|skipped [default|latest|<version>]
#       in a later step, which gets the orb's $BASH_ENV: checks go on PATH,
#       DD_TRACER_VERSION_GO, that the step and a Bash script that it starts
#       still have both folders around the toolchain's go, that the script
#       keeps the step's PATH and go, that each module's test event reaches a
#       local intake only when instrumented, that a failing test still fails,
#       and that go test leaves the projects' files unchanged.
#
# "default" is the orb's go_tracer_version default. SMOKE_FAIL=1 makes the
# modules' test fail.
set -euo pipefail

fail() {
  echo "Error: $1" >&2
  exit 1
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir=/tmp/go-check
project_dir="$state_dir/project"
path_before_dir="$state_dir/path-before"
path_after_dir="$state_dir/path-after"

# Prints the position of the first entry of the PATH $1 that is $2, or nothing.
path_position() {
  local position=0 entry rest="$1:"
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"
    rest="${rest#*:}"
    if [ "$entry" = "$2" ]; then
      echo "$position"
      return
    fi
    position=$((position + 1))
  done
}

# The folders that prepare wrote to $BASH_ENV stay on the PATH $2, which $1
# has, in the order written: in front of the toolchain's go and behind it.
check_earlier_path() {
  local where="$1" path="$2" go_dir before toolchain after
  go_dir="$(dirname "$(cat "$state_dir/toolchain-go.path")")"
  before="$(path_position "$path" "$path_before_dir")"
  toolchain="$(path_position "$path" "$go_dir")"
  after="$(path_position "$path" "$path_after_dir")"
  [ -n "$before" ] && [ -n "$after" ] || fail "$where lost a folder that an earlier step put on PATH: $path"
  [ -n "$toolchain" ] || fail "$where has no $go_dir on PATH: $path"
  [ "$before" -lt "$toolchain" ] && [ "$toolchain" -lt "$after" ] ||
    fail "$where does not have $path_before_dir, $go_dir and $path_after_dir in that order on PATH: $path"
  echo "PASS: $where keeps $path_before_dir in front of $go_dir and $path_after_dir behind it on PATH"
}

prepare() {
  local layout="$1"
  local modules=()
  case "$layout" in
    root) modules=(go-smoke) ;;
    multiple_modules) modules=(go-smoke/services/payments go-smoke/services/orders) ;;
    *) fail "Unknown layout: $layout" ;;
  esac
  mkdir -p "$project_dir"
  local module_dir package_name
  for module_dir in "${modules[@]}"; do
    # A package name has no hyphen.
    package_name="$(basename "$module_dir" | tr -d -)"
    mkdir -p "$project_dir/$module_dir"
    printf 'module example.com/smoke/%s\n\ngo 1.22\n' "$package_name" > "$project_dir/$module_dir/go.mod"
    cat > "$project_dir/$module_dir/smoke_test.go" <<EOF
package $package_name

import (
	"os"
	"testing"
)

func TestSmoke(t *testing.T) {
	if os.Getenv("SMOKE_FAIL") == "1" {
		t.Fatal("SMOKE_FAIL is set")
	}
}
EOF
  done
  printf '%s\n' "${modules[@]}" > "$state_dir/modules"
  cp -R "$project_dir/go-smoke" "$state_dir/go-smoke.before"
  command -v go > "$state_dir/toolchain-go.path"

  # Relative to $PATH, as earlier steps write them: the installer's Bash reads
  # $BASH_ENV again, so its PATH has each folder twice, and the orb must still
  # keep both.
  [ -n "${BASH_ENV:-}" ] || fail "BASH_ENV is not set"
  mkdir -p "$path_before_dir" "$path_after_dir"
  echo "export PATH=$path_before_dir:\$PATH" >> "$BASH_ENV"
  echo "export PATH=\$PATH:$path_after_dir" >> "$BASH_ENV"
}

check() {
  local expected_go="$1"
  local expected_version="${2:-}"
  local go_path toolchain_go reporting
  go_path="$(command -v go)"
  toolchain_go="$(cat "$state_dir/toolchain-go.path")"
  echo "go: $go_path (before the orb: $toolchain_go)"
  case "$expected_go" in
    instrumented)
      reporting=reported
      [ "$go_path" != "$toolchain_go" ] || fail "go is still the toolchain's, $go_path, not ddtest's go command"
      if [ "$expected_version" = "default" ]; then
        expected_version="$(awk '/^  go_tracer_version:/ { input = 1 } input && /^    default:/ { gsub(/[ \047\r]/, "", $2); print $2; exit }' "$repo_dir/src/commands/autoinstrument.yml")"
      elif [ "$expected_version" = "latest" ]; then
        # GitHub redirects releases/latest to the newest release's tag.
        expected_version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/DataDog/ddtest/releases/latest)"
        expected_version="${expected_version##*/}"
      fi
      [ -n "$expected_version" ] || fail "no expected ddtest version"
      [ "${DD_TRACER_VERSION_GO:-}" = "$expected_version" ] || fail "ddtest ${DD_TRACER_VERSION_GO:-?} was installed, not $expected_version"
      ;;
    skipped)
      reporting=unreported
      [ "$go_path" = "$toolchain_go" ] || fail "go is $go_path, not the toolchain's $toolchain_go, though Go was skipped"
      [ -z "${DD_TRACER_VERSION_GO:-}" ] || fail "DD_TRACER_VERSION_GO is '$DD_TRACER_VERSION_GO', though Go was skipped"
      ;;
    *) fail "Expected instrumented or skipped, got '$expected_go'" ;;
  esac

  check_earlier_path "the step" "$PATH"

  # Every Bash script that a step starts reads $BASH_ENV again; it must still
  # find what the step put first on PATH, and the same go as the step.
  [ -n "${BASH_ENV:-}" ] || fail "BASH_ENV is not exported, so Bash scripts that the step starts would not read it"
  local tool_dir="$state_dir/step-tools" nested_output nested_go nested_path
  mkdir -p "$tool_dir"
  printf '#!/bin/sh\necho step tool\n' > "$tool_dir/go-check-step-tool"
  chmod +x "$tool_dir/go-check-step-tool"
  cat > "$state_dir/nested-script.sh" <<'EOF'
#!/usr/bin/env bash
command -v go-check-step-tool >/dev/null || { echo "PATH: $PATH" >&2; exit 1; }
command -v go
echo "$PATH"
EOF
  chmod +x "$state_dir/nested-script.sh"
  nested_output="$(PATH="$tool_dir:$PATH" "$state_dir/nested-script.sh")" ||
    fail "a Bash script started with $tool_dir first on PATH does not find go-check-step-tool there"
  { IFS= read -r nested_go; IFS= read -r nested_path; } <<< "$nested_output"
  [ "$nested_go" = "$go_path" ] || fail "go is $nested_go in a Bash script that the step starts, not $go_path"
  echo "PASS: a Bash script that the step starts keeps the step's PATH and runs $nested_go"
  check_earlier_path "a Bash script that the step starts" "$nested_path"

  cd "$project_dir"
  local module_dir
  while IFS= read -r module_dir; do
    # go test passes, and its test's event reaches the intake only when
    # ddtest instruments it.
    "$repo_dir/tests/go-reporting.sh" "$module_dir" TestSmoke "$reporting"
    if (cd "$module_dir" && SMOKE_FAIL=1 go test -count=1 ./...) > "$state_dir/failing.log" 2>&1; then
      cat "$state_dir/failing.log"
      fail "a failing test must fail go test in $module_dir"
    fi
  done < "$state_dir/modules"

  # go test leaves the projects' files, go.mod included, as they were.
  diff -r "$state_dir/go-smoke.before" go-smoke || fail "go test changed the projects' files"
  echo "PASS: Go $expected_go"
}

case "${1:-}" in
  prepare) prepare "${2:-root}" ;;
  check) check "${2:-}" "${3:-}" ;;
  *) fail "usage: tests/go-check.sh prepare root|multiple_modules | check instrumented|skipped [default|latest|<version>]" ;;
esac
