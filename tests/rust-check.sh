#!/usr/bin/env bash
# The CI's Rust checks around the orb's autoinstrument command, in two steps of
# one job:
#
#   tests/rust-check.sh prepare
#       before the orb: writes a Cargo project into /tmp/rust-check/project;
#   tests/rust-check.sh check default|latest|<version>
#       in a later step, which gets the orb's $BASH_ENV: checks
#       RUSTC_WORKSPACE_WRAPPER and DD_TRACER_VERSION_RUST, that cargo test
#       reports to a local intake, and that a failing test still fails.
#
# "default" is the orb's rust_tracer_version default. SMOKE_FAIL=1 makes the
# project's test fail.
set -euo pipefail

fail() {
  echo "Error: $1" >&2
  exit 1
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir=/tmp/rust-check
project_dir="$state_dir/project"

prepare() {
  mkdir -p "$project_dir/src"
  cat > "$project_dir/Cargo.toml" <<'EOF'
[package]
name = "rust-smoke"
version = "0.1.0"
edition = "2021"
EOF
  cat > "$project_dir/src/lib.rs" <<'EOF'
pub fn add(left: u64, right: u64) -> u64 {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_smoke() {
        assert_eq!(add(2, 2), 4);
        if std::env::var("SMOKE_FAIL").as_deref() == Ok("1") {
            panic!("SMOKE_FAIL is set");
        }
    }
}
EOF
}

check() {
  local expected_version="$1"
  local wrapper="${RUSTC_WORKSPACE_WRAPPER:-}"
  echo "RUSTC_WORKSPACE_WRAPPER: ${wrapper:-(unset)}"
  [ -n "$wrapper" ] || fail "RUSTC_WORKSPACE_WRAPPER is not set"
  case "$wrapper" in
    /*) ;;
    *) fail "RUSTC_WORKSPACE_WRAPPER=$wrapper is not an absolute path" ;;
  esac
  [ -x "$wrapper" ] || fail "RUSTC_WORKSPACE_WRAPPER=$wrapper is not executable"
  if [ -n "${DD_TRACER_FOLDER:-}" ]; then
    [ "$wrapper" = "$DD_TRACER_FOLDER/dd-test-wrapper" ] ||
      fail "RUSTC_WORKSPACE_WRAPPER=$wrapper is not in DD_TRACER_FOLDER=$DD_TRACER_FOLDER"
  fi

  if [ "$expected_version" = "default" ]; then
    expected_version="$(awk '/^  rust_tracer_version:/ { input = 1 } input && /^    default:/ { gsub(/[ \047\r]/, "", $2); print $2; exit }' "$repo_dir/src/commands/autoinstrument.yml")"
  elif [ "$expected_version" = "latest" ]; then
    # GitHub redirects releases/latest to the newest release's tag.
    expected_version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/DataDog/dd-test-rs/releases/latest)"
    expected_version="${expected_version##*/}"
  fi
  [ -n "$expected_version" ] || fail "no expected dd-test-rs version"
  [ "${DD_TRACER_VERSION_RUST:-}" = "$expected_version" ] ||
    fail "dd-test-rs ${DD_TRACER_VERSION_RUST:-?} was installed, not $expected_version"

  cd "$project_dir"
  "$repo_dir/tests/reporting.sh" "$project_dir" test_smoke reported cargo test
  if SMOKE_FAIL=1 cargo test > "$state_dir/failing.log" 2>&1; then
    cat "$state_dir/failing.log"
    fail "a failing test must fail cargo test"
  fi
  echo "PASS: Rust instrumented with dd-test-rs $expected_version"
}

case "${1:-}" in
  prepare) prepare ;;
  check) check "${2:-}" ;;
  *) fail "usage: tests/rust-check.sh prepare | check default|latest|<version>" ;;
esac
