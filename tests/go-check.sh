#!/usr/bin/env bash
# The CI's Go checks around the orb's autoinstrument command, in two steps of
# one job, as users run them:
#
#   tests/go-check.sh prepare root|multiple_modules
#       before the orb: writes Go modules that declare go 1.22 into
#       /tmp/go-check/project and records the toolchain's go;
#   tests/go-check.sh check instrumented|skipped [default|latest|<version>]
#       in a later step, which gets the orb's $BASH_ENV: checks go on PATH,
#       DD_TRACER_VERSION_GO, that each module's test event reaches a local
#       intake only when instrumented, that a failing test still fails, and
#       that go test leaves the projects' files unchanged.
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
