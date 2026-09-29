#!/usr/bin/env bash
# Applies the repository settings described in docs/MAINTAINING.md with the
# GitHub CLI (https://cli.github.com), logged in as the repository owner:
#     gh auth login
#
#   scripts/github/configure-github.sh create     # create the empty public repository
#   (push main, then:)
#   scripts/github/configure-github.sh settings   # apply every setting below
#   scripts/github/configure-github.sh show       # print the current settings
#
# Safe to run again: every step sets the same values.
set -euo pipefail
OWNER="${OWNER:-McDaddyYuki}"
NAME="${NAME:-BlizzUI-Reborn}"
REPO="$OWNER/$NAME"
HERE="$(cd "$(dirname "$0")" && pwd)"

need() { command -v "$1" >/dev/null || { echo "Needs $1"; exit 1; }; }
need gh

create() {
  if gh repo view "$REPO" >/dev/null 2>&1; then echo "$REPO already exists."; return; fi
  gh repo create "$REPO" --public \
    --description "Retail-style HUD Edit Mode, layouts and Boss Timeline for the WoW 3.3.5a client." \
    --disable-wiki
  echo "Created https://github.com/$REPO (empty). Push main next:"
  echo "  git remote add origin https://github.com/$REPO.git && git push -u origin main"
}

settings() {
  gh api "repos/$REPO" >/dev/null || { echo "Repository $REPO not found."; exit 1; }
  local me; me="$(gh api user --jq .login)"
  [ "$me" = "$OWNER" ] || { echo "Logged in as $me, not $OWNER."; exit 1; }

  echo "- Repository features and merge options"
  gh api -X PATCH "repos/$REPO" --silent \
    -F has_issues=true -F has_projects=false -F has_wiki=false -F has_discussions=false \
    -F allow_auto_merge=false \
    -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
    -F delete_branch_on_merge=true -F allow_update_branch=true -F allow_forking=true \
    -F web_commit_signoff_required=false
  gh api -X PUT "repos/$REPO/topics" --silent -f 'names[]=world-of-warcraft' -f 'names[]=wow-addon' \
    -f 'names[]=wotlk' -f 'names[]=edit-mode' -f 'names[]=lua'

  echo "- GitHub Actions: GitHub-made actions only; read-only token; can't approve pull requests"
  gh api -X PUT "repos/$REPO/actions/permissions" --silent -F enabled=true -f allowed_actions=selected
  gh api -X PUT "repos/$REPO/actions/permissions/selected-actions" --silent \
    -F github_owned_allowed=true -F verified_allowed=false
  gh api -X PUT "repos/$REPO/actions/permissions/workflow" --silent \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  echo "- Workflows from outside contributors wait for approval"
  gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --silent \
    -f approval_policy=all_external_contributors

  echo "- Private vulnerability reporting"
  gh api -X PUT "repos/$REPO/private-vulnerability-reporting" --silent

  echo "- 'release' environment: only v* tags, publishing needs $OWNER's approval"
  local uid; uid="$(gh api "users/$OWNER" --jq .id)"
  gh api -X PUT "repos/$REPO/environments/release" --silent --input - <<JSON
{ "wait_timer": 0, "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": $uid } ],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
  if ! gh api "repos/$REPO/environments/release/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx 'v*'; then
    gh api -X POST "repos/$REPO/environments/release/deployment-branch-policies" --silent -f name='v*' -f type=tag
  fi

  echo "- Rulesets: protect main, protect release tags"
  for f in ruleset-main.json ruleset-tags.json; do
    local rname; rname="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$HERE/$f")"
    local id; id="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name==\"$rname\") | .id" || true)"
    if [ -n "$id" ]; then gh api -X PUT "repos/$REPO/rulesets/$id" --silent --input "$HERE/$f"
    else gh api -X POST "repos/$REPO/rulesets" --silent --input "$HERE/$f"; fi
  done

  echo "- Collaborators with access (should be only $OWNER):"
  gh api "repos/$REPO/collaborators?affiliation=all" --jq '.[] | "    \(.login): \(.role_name)"'
  local others; others="$(gh api "repos/$REPO/collaborators?affiliation=all" --jq "[.[] | select(.login != \"$OWNER\")] | length")"
  [ "$others" = "0" ] || echo "  WARNING: other people have access. Remove them under Settings > Collaborators."
  echo "Done."
}

show() {
  gh api "repos/$REPO" --jq '{visibility, has_issues, has_wiki, has_projects, allow_auto_merge, allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge}'
  gh api "repos/$REPO/actions/permissions/workflow"
  gh api "repos/$REPO/rulesets" --jq '.[] | "\(.name): \(.enforcement)"'
  gh api "repos/$REPO/environments/release" --jq '{name, protection_rules}'
  gh api "repos/$REPO/collaborators?affiliation=all" --jq '.[] | "\(.login): \(.role_name)"'
}

case "${1:-}" in
  create) create ;;
  settings) settings ;;
  show) show ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
