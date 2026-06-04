#!/usr/bin/env bash
# Goes in: scripts/setup-branch-gate.sh  (run once, from anywhere)
#
# Creates a repository RULESET that requires the "ansible-lint" check to pass
# before anything can merge into main. Rulesets are the modern replacement for
# classic branch-protection rules and apply to everyone (incl. admins) unless
# you add a bypass actor.
#
# Requires:
#   * gh CLI authenticated as a repo admin:   gh auth login
#   * a plan that supports rulesets on PRIVATE repos (Pro / Team / Enterprise Cloud).
#     Free + private cannot enforce this server-side.
#
# Re-running POSTs a second ruleset; to change settings, edit in the UI
# (Settings -> Rules -> Rulesets) or DELETE then re-run.

set -euo pipefail

REPO="docker-hc/Ansible_Simulator_Lab"
BRANCH="main"
CHECK_CONTEXT="ansible-lint"   # MUST equal the job name in ansible-lint.yml

RULESET=$(cat <<JSON
{
  "name": "main-lint-gate",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["refs/heads/${BRANCH}"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "${CHECK_CONTEXT}" }
        ]
      }
    }
  ]
}
JSON
)

echo ">> Creating ruleset 'main-lint-gate' on ${REPO} ..."
echo "$RULESET" | gh api --method POST "repos/${REPO}/rulesets" --input -
echo ">> Done. Confirm under: Settings -> Rules -> Rulesets -> main-lint-gate"
echo ">> Note: the 'pull_request' rule means changes to main must go through a PR"
echo "         (0 approvals required), which is what lets the check act as a gate."
echo "         Set strict_required_status_checks_policy=true later if you want"
echo "         'branch must be up to date before merging' (more friction, solo-unfriendly)."
