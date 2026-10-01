# Debian game deployment

Public rough preview: https://game.4mn.org. The owner authorized public deployment on 2026-10-01. This uses the existing Debian host (`ssh debian`, user `ben`), Nginx in Docker, and a dedicated Cloudflare tunnel. It does not require changing the shared Nginx Proxy Manager or restarting the shared system tunnel.

## Layout

- Compose project: `/home/ben/aoem`, configuration copied from `deploy/`.
- Static releases: `/home/ben/aoem/site/releases/<release-id>/`.
- Active relative symlink: `/home/ben/aoem/site/current`.
- Origin smoke endpoint: `http://127.0.0.1:3062/` on Debian, bound to loopback.
- Containers: `aoem-game` and `aoem-game-tunnel`, both restart automatically.
- Tunnel: `aoem-game`, UUID `a81df93e-953f-4e38-9e7f-a5d208f1af1d`.
- Tunnel credential: `/home/ben/.cloudflared/a81df93e-953f-4e38-9e7f-a5d208f1af1d.json`, mode `0400`; mounted read-only. Never copy it into the repository, artifact, or static directory.

## Build and publish

Commit the runtime and packaging changes, then export with Godot 4.6:

```sh
tools/build_mobile_web_beta.sh build/game-web-2026-10-01
```

Verify the closed payload checksum manifest and the packaging verifier before copying. Copy only the chosen exported directory, not the parent build directory or project. The export excludes developer tools, debug/MCP wiring, docs, deployment configuration, and credentials.

Copy the three `deploy/` files to `/home/ben/aoem/`, and stream the artifact into a new release directory using `COPYFILE_DISABLE=1 tar` over SSH. Run `sha256sum -c SHA256SUMS.txt` within that directory. Switch `site/current` with a relative symlink and atomic `mv -Tf`, so the existing read-only parent mount sees the new release.

From `/home/ben/aoem` on Debian:

```sh
docker compose config --quiet
docker compose run --rm --no-deps aoem nginx -t
docker compose up -d
```

The initial DNS route is created once using the existing authenticated Cloudflare CLI:

```sh
cloudflared tunnel route dns aoem-game game.4mn.org
```

Check trusted public HTTPS, correct WASM/JS/PCK MIME types, compression, `version.json`, all payload hashes, and actual browser startup. Complete an online reload with a controlling service worker before testing an offline reload. Keep at least the previous verified release for rollback.

## Rollback and stop

On Debian, atomically replace `site/current` with the previous release's relative symlink:

```sh
cd /home/ben/aoem/site
ln -s releases/PREVIOUS_RELEASE current.next
mv -Tf current.next current
```

To stop this game only, run `docker compose down` from `/home/ben/aoem`. Existing sites and tunnels are independent. Installed PWA clients can keep a prior service worker until all game windows close; reopen online after a release or rollback.

## Phone installation

On iPhone, open the URL in Safari and use Share → Add to Home Screen; launch the new icon for standalone display. On Android, use the browser's Install/Add to Home Screen action. Landscape is the intended orientation. Browser fullscreen availability varies; the installed standalone app removes the normal browser address bar.

This is a rough public preview. Desktop browser automation does not certify physical-phone touch behavior, safe areas, audio, or prolonged performance.
