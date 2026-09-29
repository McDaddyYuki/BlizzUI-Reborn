# Security

BlizzUI Reborn runs inside the World of Warcraft client, which sandboxes addons. The areas where a mistake could matter are the ones that read text from other people:

- the layout **Import** dialog;
- the **Boss Timeline data** import (`BRK1:`/`BRK2:`/`BRK3:` strings).

Both are parsed as plain data and are never run as code. If you find a way around that, or anything else that could harm a player who uses the addon or pastes a shared string, please report it privately.

**How to report:** open this repository's **Security** tab and choose **Report a vulnerability**. That starts a private report only the maintainer can see. Please include the addon version and a minimal example string or steps. You'll get an answer when the maintainer has looked at it. Fixes are published as a normal release, with credit if you want it.

Please don't open public issues for security problems.
