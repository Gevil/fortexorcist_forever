# Security

ForteXorcist Forever is a Lua addon for the WoW Forever client. It has no network access and sends no
data outside the game. It can send addon-channel messages to other players in your group (Warlock group
comms, on by default, never solo) and, only if you enable them, chat announcements.

Report a vulnerability, or anything that could expose a player (for example a message that leaks private
data, or a way to make the addon send chat the player did not enable), **privately**: use GitHub's
"Report a vulnerability" on <https://github.com/Gevil/fortexorcist_forever/security/advisories/new>.
Do not open a public issue for it. You will get an answer when the maintainer has read it; there is
no fixed response time.

Supported version: the latest release.

Saved variables and `/fx probe` output can contain your character's name; check them before you post
them in a public issue.
