#!/usr/bin/env bats
load helpers/common

# Builds: origin (bare) with main = A-B, feature = A-B-C.
setup() {
  setup_tmp
  git_q init --bare "$TMP/origin.git"
  git_q clone "$TMP/origin.git" "$TMP/seed"
  cd "$TMP/seed"
  git_q commit --allow-empty -m A
  git_q commit --allow-empty -m B
  git_q push origin HEAD:main
  git_q checkout -b feature
  git_q commit --allow-empty -m C
  git_q push origin feature
  MAIN_SHA="$(git rev-parse main)"
  FEATURE_SHA="$(git rev-parse feature)"
  git_q clone "$TMP/origin.git" "$TMP/work"
  cd "$TMP/work"
}
teardown() { teardown_tmp; }

@test "commit on main passes" {
  run "$SCRIPTS/prod_guard.sh" "$MAIN_SHA" main
  [ "$status" -eq 0 ]
  [[ "$output" == *"is on 'main'"* ]]
}

@test "default branch is main" {
  run "$SCRIPTS/prod_guard.sh" "$MAIN_SHA"
  [ "$status" -eq 0 ]
}

@test "commit only on feature branch is rejected" {
  run "$SCRIPTS/prod_guard.sh" "$FEATURE_SHA" main
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on any prod branch (main)"* ]]
  [[ "$output" == *"TROUBLESHOOTING.md#prod-guard-rejected"* ]]
}

@test "any of several prod branches is accepted" {
  run "$SCRIPTS/prod_guard.sh" "$FEATURE_SHA" main feature
  [ "$status" -eq 0 ]
}

@test "missing prod branches are reported" {
  run "$SCRIPTS/prod_guard.sh" "$MAIN_SHA" release
  [ "$status" -eq 1 ]
  [[ "$output" == *"none of the prod branches"* ]]
}

@test "works from a shallow single-commit clone (Xcode Cloud)" {
  cd "$TMP" && rm -rf "$TMP/work"
  git_q clone --depth 1 --branch feature "file://$TMP/origin.git" "$TMP/shallow"
  cd "$TMP/shallow"
  [ "$(git rev-parse --is-shallow-repository)" = true ]
  run "$SCRIPTS/prod_guard.sh" "$FEATURE_SHA" main
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on any prod branch"* ]]
  run "$SCRIPTS/prod_guard.sh" "$(git rev-parse HEAD~1)" main
  [ "$status" -eq 0 ]
}

@test "unknown commit fails" {
  run "$SCRIPTS/prod_guard.sh" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef main
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in this clone"* ]]
}
