# lineagent-landing

GitHub Pages site for **www.lineagent.ai** — hosts:

- `index.html` — landing page
- `install-info.json` — stable release discovery for Lineage's updater and agent-mediated installs (written only by the release pipeline)

Custom domain: `www.lineagent.ai` (DNS CNAME → `nowa.github.io`).

Don't hand-edit `install-info.json` — let the release pipeline update it.

This site hosts no executable installer. The direct installer is the
version-bound `lineage-installer.sh` release asset in
[`nowa/lineage-releases`](https://github.com/nowa/lineage-releases); the page's
install command switches to it when the first release is promoted.
