# lineagent-landing

GitHub Pages site for **www.lineagent.ai** — hosts:

- `index.html` — landing page
- `install.sh` — one-liner installer (copy of `nowa/lineage:install.sh`)
- `install-info.json` — release metadata consumed by install.sh + agent-mediated installs (auto-updated by `nowa/lineage`'s release.yml on each tag push)

Custom domain: `www.lineagent.ai` (DNS CNAME → `nowa.github.io`).

Don't hand-edit `install-info.json` — let the release pipeline update it.
