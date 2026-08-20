#!/usr/bin/env bash
#
# Spin up a local Conductor OSS stack and run the integration spec suite
# against it, mirroring the `integration-tests-oss` job in
# .github/workflows/ci.yml. Orkes-Enterprise-only specs/examples are skipped
# via the existing `skip: !ENV['CONDUCTOR_INTEGRATION']` pattern extended with
# an OSS-aware condition (see the individual spec files for the
# empirically-confirmed gaps).
#
# The stack (Conductor OSS + Postgres) is defined in
# scripts/docker-compose-oss.yaml and is torn down automatically on exit.
#
# Usage:
#   scripts/run-integration-oss.sh [--keep-up] [--version <tag>] [-- rspec args]
# Examples:
#   scripts/run-integration-oss.sh
#   scripts/run-integration-oss.sh --version 3.32.0-rc18
#   scripts/run-integration-oss.sh --keep-up
#   scripts/run-integration-oss.sh -- spec/integration/workflow_spec.rb
set -euo pipefail

KEEP_UP=0
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-up) KEEP_UP=1; shift ;;
    --version) OSS_CONDUCTOR_VERSION="${2:?--version needs a tag}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--keep-up] [--version <tag>] [-- rspec args]"
      exit 0
      ;;
    --) shift; extra=("$@"); break ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

export OSS_CONDUCTOR_VERSION="${OSS_CONDUCTOR_VERSION:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-oss.yaml"
cd "${REPO_ROOT}"

compose() { docker compose -f "${COMPOSE_FILE}" "$@"; }

cleanup() {
  if [[ "${KEEP_UP}" == "1" ]]; then
    echo "--keep-up set: leaving the OSS stack running. Tear down with:"
    echo "  docker compose -f ${COMPOSE_FILE} down -v"
    return
  fi
  echo "Tearing down Conductor OSS stack..."
  compose down -v || true
}
trap cleanup EXIT

echo "Starting Conductor OSS stack (conductoross/conductor:${OSS_CONDUCTOR_VERSION})..."
compose up -d

echo "Waiting for Conductor to be healthy..."
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
deadline=$(( SECONDS + HEALTH_TIMEOUT ))
until curl -sf http://localhost:8080/health >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Error: Conductor did not become healthy within ${HEALTH_TIMEOUT}s." >&2
    compose logs conductor-server || true
    exit 1
  fi
  sleep 5
done
echo "Conductor is up."

export CONDUCTOR_SERVER_URL="http://localhost:8080/api"
export CONDUCTOR_SERVER_TYPE="oss"
export CONDUCTOR_INTEGRATION="true"

bundle exec rspec spec/integration/ --format documentation ${extra[@]+"${extra[@]}"}
