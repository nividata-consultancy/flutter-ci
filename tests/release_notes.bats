#!/usr/bin/env bats
load helpers/common

setup() {
  setup_tmp
  git_q init "$TMP/repo"
  cd "$TMP/repo"
  git_q commit --allow-empty -m "Initial"
  git_q tag v1.0.0
  git_q commit --allow-empty -m "Old beta work"
  git_q tag v1.1.0-beta.1
  for i in 1 2 3 4 5 6 7; do git_q commit --allow-empty -m "Change $i"; done
}
teardown() { teardown_tmp; }

@test "uat header and commits since previous tag" {
  run "$SCRIPTS/release_notes.sh" v1.1.0-beta.2
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "[UAT] v1.1.0-beta.2 · "* ]]
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[1]}" = "- Change 7" ]
}

@test "prod notes compare with previous prod tag" {
  run "$SCRIPTS/release_notes.sh" v1.1.0 --max-commits 20
  [[ "${lines[0]}" == "[PROD] v1.1.0 · "* ]]
  [[ "$output" == *"Old beta work"* ]]
  [[ "$output" != *"Initial"* ]]
}

@test "respects byte limit and keeps valid UTF-8" {
  git_q commit --allow-empty -m "$(printf 'é%.0s' $(seq 1 200))"
  run "$SCRIPTS/release_notes.sh" v1.1.0-beta.3 --max-bytes 120
  [ "$status" -eq 0 ]
  bytes="$(printf '%s' "$output" | LC_ALL=C wc -c | tr -d ' ')"
  [ "$bytes" -le 120 ]
  printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null
}

@test "stays under 1 KB by default with long subjects" {
  for i in 1 2 3 4 5; do git_q commit --allow-empty -m "$(printf 'x%.0s' $(seq 1 400))"; done
  run "$SCRIPTS/release_notes.sh" v1.1.0-beta.3
  bytes="$(printf '%s\n' "$output" | LC_ALL=C wc -c | tr -d ' ')"
  [ "$bytes" -le 1000 ]
}

@test "invalid tag fails" {
  run "$SCRIPTS/release_notes.sh" v1.1
  [ "$status" -eq 1 ]
}
