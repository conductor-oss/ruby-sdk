#!/usr/bin/env bash
# Run all agent examples against an existing playback-enabled Conductor server.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
conductor_dir=$(cd "${1:?Usage: run-agents-playback.sh CONDUCTOR_CHECKOUT}" && pwd)
cd "$repo_dir"
export CONDUCTOR_SERVER_URL=${CONDUCTOR_SERVER_URL:-http://localhost:8080/api}
export CONDUCTOR_AGENT_LLM_MODEL=mock/mockLLM
export CONDUCTOR_AGENTS_PLAYBACK=true
export CONDUCTOR_RECORDINGS_DIR="$conductor_dir/llm-recordings"
export GITHUB_REPOS_URL='http://localhost:3002/users/Conductor/repos?per_page=5&sort=updated'
mkdir -p tmp
playback_dir=${CONDUCTOR_PLAYBACK_WORK_DIR:-$(mktemp -d "$repo_dir/tmp/agent-playback.XXXXXX")}
mkdir -p "$playback_dir"
playback_dir=$(cd "$playback_dir" && pwd)
verify_script="$conductor_dir/.github/actions/check-playback/check-playback.sh"
[[ -f "$verify_script" && -d "$CONDUCTOR_RECORDINGS_DIR" ]]
curl --fail --silent --show-error --max-time 10 "${CONDUCTOR_SERVER_URL%/api}/health" > /dev/null
ruby_command=()
worker_container=""
if ! command -v bundle > /dev/null; then
  worker_container="ruby-agent-workers-$$"
  ruby_command=(docker run --rm --network host
    -v "$repo_dir:$repo_dir:z" -w "$repo_dir"
    -v "$playback_dir:$playback_dir:z"
    -v ruby-sdk-bundle:/usr/local/bundle:z
    -e CONDUCTOR_SERVER_URL -e CONDUCTOR_AGENT_LLM_MODEL
    -e CONDUCTOR_AGENTS_PLAYBACK -e GITHUB_REPOS_URL
    -e CONDUCTOR_AUTH_KEY -e CONDUCTOR_AUTH_SECRET)
fi
run_ruby() {
  if ((${#ruby_command[@]})); then
    "${ruby_command[@]}" ruby:3.3 "$@"
  else
    "$@"
  fi
}
run_ruby bundle check

pids=()
cleanup() {
  if [[ -n "$worker_container" ]]; then
    docker stop --time 10 "$worker_container" > /dev/null 2>&1 || true
  fi
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${CONDUCTOR_PLAYBACK_SERVICES_STARTED:-false}" == true ]]; then
  bash .github/scripts/start-agent-services.sh "$conductor_dir" --check
else
  CONDUCTOR_PLAYBACK_WORK_DIR="$playback_dir" bash .github/scripts/start-agent-services.sh "$conductor_dir"
  pids+=("$(cat "$playback_dir/http.pid")" "$(cat "$playback_dir/mcp.pid")")
fi

if [[ -n "$worker_container" ]]; then
  "${ruby_command[@]}" --name "$worker_container" ruby:3.3 \
    bundle exec ruby -Ilib examples/agents/external_workers.rb > "$playback_dir/workers.log" 2>&1 &
else
  bundle exec ruby -Ilib examples/agents/external_workers.rb > "$playback_dir/workers.log" 2>&1 &
fi
pids+=("$!")

echo "Running ALL agent examples against $CONDUCTOR_SERVER_URL"
echo "Logs: $playback_dir"
# Run verification even if an example fails, preserving both results.
test_status=0
run_ruby bundle exec rspec spec/integration/agents/ --format documentation \
  --format json --out "$playback_dir/results.json" 2>&1 | tee "$playback_dir/tests.log" || test_status=$?
verify_status=0
sh "$verify_script" "$CONDUCTOR_SERVER_URL" \
  2>&1 | tee "$playback_dir/verify.log" || verify_status=$?
if ((test_status != 0)); then exit "$test_status"; fi
exit "$verify_status"
