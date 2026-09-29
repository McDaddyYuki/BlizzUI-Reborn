# Contributing to BlizzUI Reborn

Thanks for helping. Bug reports, ideas and pull requests are all welcome. Please read this first: the project is maintained by one person, and **every change is a proposal until the maintainer approves it.** Opening a pull request never gives anyone write access, and nothing is merged or released automatically.

## Reporting a bug

Use **Issues → New issue → Bug report**. The most useful things to include:

- the addon version (`/br report` shows it), your client build and your server;
- the exact Lua error text (turn errors on with `/console scriptErrors 1`), or what you saw and what you expected;
- the output of `/br report` (it's copyable);
- which other addons you use, especially Deadly Boss Mods, BigWigs, Carbonite and Bagnon.

**Don't post:** account names, passwords, e-mail addresses, whole `WTF` folders or other addons' files. If a SavedVariables excerpt helps, paste only the part about `BlizzUIRebornDB`, and remove anything personal.

Security problems (for example something that could run code from a shared string) go through **Security → Report a vulnerability**, not a public issue. See [SECURITY.md](SECURITY.md).

## Suggesting a feature

Use **Issues → New issue → Feature request**. The project's scope:

- It brings Retail's HUD Edit Mode and Boss Timeline *functionality* to 3.3.5a.
- The game's own look is kept: stock frames, colours and art, with no custom textures or borders.
- Only APIs that exist in the 3.3.5a client are used.
- No encounter data from other addons is bundled, and nothing is copied from them.

## Proposing a code change

1. Fork the repository and create a branch from `main`.
2. Make the change. Keep it focused on one thing.
3. Run the checks locally (below) and make sure they pass.
4. Add a line under the top section of `CHANGELOG.md` describing the change for players.
5. Open a pull request and fill in the template.

After that:

- The automated checks (Lua 5.1 compatibility, regression tests and a package check) run on your pull request once the maintainer approves the run. This is a GitHub setting for outside contributors.
- The maintainer may ask for changes, edit the pull request, squash it, or decline it.
- Only the maintainer merges pull requests and publishes releases. A merged change ships in the next release the maintainer chooses to publish.

### Rules for code

- **Lua 5.1** (the game's version). Don't use `goto`, integer division `//`, bitwise operators, `table.unpack`, or `load` with a string.
- **3.3.5a API only.** No Retail functions such as `SetShown`, `SetSize`, `C_Timer`, `Mixin`, `SetColorTexture` or `SetAtlas`. `tools/lint51.py` rejects the common ones.
- **No protected-frame changes in combat.** Secure/protected frames are only moved or changed out of combat. Queue the change otherwise, as the existing code does.
- **No field writes on Blizzard frames and no replacing Blizzard functions.** Use `hooksecurefunc`-style post-hooks (`A:Hook`), as the existing code does, to avoid taint.
- **Stock art only.** Reference game textures by path. Don't add image files.
- **No third-party code or data.** Don't copy code, tables or timings from Deadly Boss Mods, BigWigs, Carbonite or any other addon. Talking to another addon through its public callbacks or messages is fine. Note any new interface of this kind in `PROVENANCE.md`.
- **No personal data** in code, tests or fixtures: no real character, account or guild names.

### Running the checks

You need Lua 5.1 (`lua5.1`) and Python 3. On Debian/Ubuntu: `sudo apt-get install lua5.1 python3`.

```sh
tools/run_all.sh                     # every scenario test + the 5.1/3.3.5 API lint
LUA=lua5.1 tools/run_all.sh          # choose the interpreter explicitly
python3 scripts/package.py 0.7.0     # build dist/BlizzUIReborn-0.7.0.zip
python3 scripts/check_package.py dist/BlizzUIReborn-0.7.0.zip 0.7.0
```

The tests run the addon against a headless simulation of the 3.3.5 client in `tools/`. New behaviour should come with a scenario in `tests/`: copy the style of an existing file, and give every `check(...)` a sentence describing what the player would see. The simulation can't show rendering or taint, so say in the pull request what you checked in the game, and on which client and server.

## Contribution terms

BlizzUI Reborn is not open source (see [LICENSE](LICENSE)). So that contributions can be used, **by submitting a pull request, patch or other contribution you agree that:**

1. The contribution is your own original work, or you otherwise have the right to submit it. It contains no code, data or assets copied from other addons, Blizzard or anyone else.
2. You keep the copyright in your contribution. You grant the maintainer of BlizzUI Reborn a perpetual, worldwide, non-exclusive, royalty-free, irrevocable licence to use, copy, modify, publish, distribute, sublicense and relicense it, as part of BlizzUI Reborn or otherwise.
3. There is no obligation to merge or use your contribution. It may be credited in the changelog or in the release notes.

If you can't agree to these terms, please open an issue describing the idea instead of sending code.

## Conduct

Be kind and assume good faith. Harassment, personal attacks or spam lead to comments being removed and, if needed, the account being blocked from the repository.
