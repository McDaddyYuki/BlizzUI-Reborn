# Maintaining BlizzUI Reborn

This page is for the maintainer. It covers how the repository is set up so that only you merge and release, how to publish the first time, and how to handle community pull requests and releases.

## Repository settings

`scripts/github/configure-github.sh settings` applies all of these. `show` prints them back.

| Area | Setting | Why |
|---|---|---|
| Visibility | Public | Anyone can read, open issues and propose changes. |
| Access | **No collaborators.** Only the owner (you) has write/admin. The script warns if anyone else has access. | Contributors work from forks, so nobody else can push, merge, tag or release. |
| Features | Issues on (with the bug and feature forms; blank issues off). Wiki, Projects and Discussions off. | Keeps reports structured. |
| Pull requests | **Auto-merge off.** Squash merging only, using the PR title and body. Merged branches are deleted. The "Update branch" button is on. | Every merge is a manual click by you, and history stays one commit per change. |
| Ruleset "Protect main" | Applies to the default branch. No deletion or force-push, linear history, changes only through a pull request. Required approvals: **0** (GitHub doesn't let you approve your own PRs, so a higher number would lock you out). New commits dismiss stale reviews, and conversations must be resolved. Required checks: *Lua 5.1 compatibility*, *Regression tests (Lua 5.1)*, *Package check*, which must come from GitHub Actions and be up to date with `main`. **No bypass list.** | Nothing reaches `main` without a pull request and green checks, including your own changes. Only you can press Merge, so a community PR stays a proposal until you do. |
| CODEOWNERS | `* @McDaddyYuki` | You're automatically asked to review every PR (not required, see above). |
| Ruleset "Protect release tags" | `v*` tags can't be created, moved or deleted except by the repository admin (you). | Only you can start a release, and published tags can't be rewritten. |
| Environment "release" | Required reviewer: you. Deployments allowed only from `v*` tags. | The Release workflow waits for your **Approve and deploy** click before anything is published. |
| Actions | Only GitHub-made actions are allowed. The workflow token is **read-only** by default and can't approve PRs. Workflows from **all outside contributors need your approval** before they run. | A fork PR can't run unreviewed workflow changes, and can't get write access or secrets (CI uses `pull_request`, never `pull_request_target`). |
| Security | Private vulnerability reporting on (see SECURITY.md). Dependabot proposes GitHub Actions updates as normal PRs. | |

The approval number is 0 on purpose. Branch protection can't require a second person on a one-person project. Your control comes from being the only account with write access: nobody else can merge, push, tag or approve the release environment. If you ever add a co-maintainer, raise the approval count to 1 and turn on "Require review from Code Owners".

## First upload

1. Install the GitHub CLI and log in as McDaddyYuki: `gh auth login`.
2. Create the empty public repository: `scripts/github/configure-github.sh create`.
3. Push the prepared history: `git remote add origin https://github.com/McDaddyYuki/BlizzUI-Reborn.git && git push -u origin main`.
4. Apply the settings: `scripts/github/configure-github.sh settings`, then check them with `... show`.
5. Wait for the first CI run on `main` (Actions tab) to pass.
6. Release 0.7.0 as described below.

Settings are applied after the first push because rulesets that require status checks would otherwise block the initial push.

## Handling a community pull request

1. Read the diff. Check especially: nothing copied from other addons, no new third-party interfaces missing from PROVENANCE.md, the contribution-terms checkbox is ticked, and there are no workflow changes you don't want.
2. Approve the workflow run ("Approve and run" on the PR) so the checks run.
3. Ask for changes, push fixes yourself (the "Allow edits by maintainers" option), or close it.
4. When you want it: **Squash and merge**. Nothing merges or releases by itself.

## Releasing

1. On a branch, set the version in `BlizzUIReborn/BlizzUIReborn.toc` (`## Version:`) and `BlizzUIReborn/Core.lua` (`A.version`). Add a `## X.Y.Z: title` section at the top of `CHANGELOG.md`.
2. Open a PR, let CI pass, and merge it.
3. Tag the merge commit on `main` and push the tag:
   ```sh
   git checkout main && git pull
   git tag -a v0.7.0 -m "BlizzUI Reborn 0.7.0"
   git push origin v0.7.0
   ```
4. The **Release** workflow runs the Lua 5.1 checks and the tests, and builds and checks `BlizzUIReborn-0.7.0.zip`. It then waits.
5. Open the run (Actions → Release) and click **Review deployments → Approve and deploy**. The GitHub release is created with the ZIP and the changelog section as notes. If you don't approve, nothing is published.

The ZIP contains one folder, `BlizzUIReborn/`: the `.toc`, the Lua files it lists, README, CHANGELOG, PROVENANCE and LICENSE.txt. `scripts/check_package.py` refuses a ZIP that has anything else, including game or account files, other addons' files, the removed DBM-derived dataset or boss-mod module code. The tag, the `.toc` and `Core.lua` must agree on the version.

## Running things locally

```sh
LUA=lua5.1 tools/run_all.sh
python3 scripts/package.py 0.7.0 && python3 scripts/check_package.py dist/BlizzUIReborn-0.7.0.zip 0.7.0
```
