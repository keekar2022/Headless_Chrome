<!-- Concept: Mukesh Kesharwani -->
<!-- Contact: mukesh.kesharwani@adobe.com -->

# Headless Chrome (Docker)

Run **Chromium in an isolated Docker container** so users can see a **normal Chrome window** in their browser — without using the host machine's Chrome install, profile, or settings.

Default mode streams a real Chromium desktop through **noVNC** at port **6080**. Optional headless **CDP** mode remains available for automation.

## Quick start

### Build locally

```bash
chmod +x scripts/build-and-push-dockerhub.sh scripts/entrypoint.sh
DOCKERHUB_PUSH=0 ./scripts/build-and-push-dockerhub.sh
```

### Run — normal Chrome window (default)

```bash
docker run --rm -d -p 6080:6080 --shm-size=2g \
  --dns 192.168.1.200 --dns 192.168.1.1 \
  --name headless-chrome keekar/headless-chrome:latest
```

Or use the reference script (reads [`deploy/defaults.env`](deploy/defaults.env)):

```bash
./deploy/docker-run.example.sh
```

Open in **any browser**:

**<http://localhost:6080/>**

On a **remote server**, replace `localhost` with the server's public IP or DNS (e.g. `http://nas.keekar.au:6080/`). The root URL auto-opens the Chrome desktop (no directory listing).

You get a full Chromium window inside the page. Browse, click, and type as usual. Everything runs in the container with a **fresh profile** — your Mac/PC Chrome settings are not used.

Optional start URL:

```bash
docker run --rm -d -p 6080:6080 --shm-size=2g \
  -e START_URL=https://example.com \
  --name headless-chrome keekar/headless-chrome:latest
```

### Run — headless automation mode (optional)

```bash
docker run --rm -d -p 9222:9222 --shm-size=2g \
  -e CHROME_MODE=headless \
  --name headless-chrome keekar/headless-chrome:latest
curl http://localhost:9222/json/version
```

### Publish to Docker Hub

```bash
docker login
./scripts/build-and-push-dockerhub.sh
```

### Automatic browser updates on restart

On **every container start or restart**, a root bootstrap refreshes signed Debian 13 (`trixie`) package metadata over HTTPS and upgrades installed packages, including Chromium, noVNC, and their dependencies. It verifies Chromium matches the repository candidate, then drops privileges and starts the browser as `chrome`. This selects current supported Debian packages, not necessarily the latest upstream Google Chrome release.

Build and deploy this updated image **once** to install the bootstrap. After that, use `docker restart headless-chrome` or `docker compose restart` to check for current packages; no version bump or image rebuild is needed just for a browser update. Updates do not happen while the browser is running.

Updates require internet access, a writable container filesystem, and root during bootstrap only. They have a ten-minute time limit; repository, signature, installation, or timeout failures **refuse browser startup** rather than silently use old packages. Set `CHROME_AUTO_UPDATE=0` only for an intentional offline or forced-non-root deployment. See [runtime update requirements and troubleshooting](docs/RUNTIME_UPDATES.md).

The build script still uses **`--pull` and `--no-cache` by default** to refresh base images. Periodic image rebuilds remain necessary for project changes and Debian release migrations. Installed versions are recorded at `/usr/share/headless-chrome/packages.txt` and refreshed after each successful bootstrap update.

For a local Compose deployment, run `docker compose build --pull --no-cache` followed by `docker compose up -d`. Compose binds noVNC to localhost and preserves cookies and settings in the `chrome-profile` volume. Treat that volume as sensitive browser data; `docker compose down -v` deletes it.

Run `bash scripts/test-browser.sh keekar/headless-chrome:latest` after building to check signed updates on startup/restart, privilege dropping, both browser modes, offline mode, and failure handling. The test uses official Debian repositories but does not access third-party websites. See [browser verification troubleshooting](docs/BROWSER_VERIFICATION.md) for Cloudflare failures and safe remote access.

On the server: pull and redeploy (`docker pull keekar/headless-chrome:latest`, then redeploy the app).

## Environment variables

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `DOCKER_BUILD_CACHE` | `0` | Set to `1` for faster builds using Docker layer cache (may skip fresh apt packages) |
| `DOCKERHUB_PUSH` | `1` | Set to `0` for local build only |
| `DOCKERHUB_USERNAME` | `keekar` | Docker Hub namespace |
| `CHROME_MODE` | `desktop` | `desktop` = visible Chrome via noVNC; `headless` = CDP only |
| `CHROME_AUTO_UPDATE` | `1` | Signed package updates on every start/restart; `0` explicitly disables runtime updates |
| `NOVNC_PORT` | `6080` | Web UI port for desktop mode |
| `START_URL` | `about:blank` | URL Chromium opens on start |
| `VNC_PASSWORD` | (none) | **Set on public servers** — VNC/noVNC password |
| `NOVNC_LISTEN` | `0.0.0.0` | Address noVNC binds to inside the container |
| `CHROME_PROFILE` | `/tmp/chrome-profile` | Isolated profile dir inside container |
| `SCREEN` | `1920x1080x24` | Virtual display size (width x height x depth); must match browser fill |
| `DNS_PRIMARY` | `192.168.1.200` | Primary DNS — set at deploy via `--dns`, compose, or TrueNAS `dns_config` |
| `DNS_SECONDARY` | `192.168.1.1` | Secondary DNS (pfSense gateway) — avoids public DNS popups/ads |

## Why this is isolated from your system

- Chromium runs **inside Docker**, not on the host
- Uses its own **`/tmp/chrome-profile`** — no host bookmarks, extensions, cookies, or env vars
- Host Chrome settings, keychain, and login state are never read

## Connect automation clients (headless mode only)

**Puppeteer:**

```javascript
const browser = await puppeteer.connect({ browserURL: 'http://localhost:9222' });
```

**Playwright:**

```javascript
const browser = await chromium.connectOverCDP('http://localhost:9222');
```

## Security

- Root is used only for the package-update bootstrap. Chromium and desktop services run as `chrome`, with no-new-privileges and cleared capabilities. Do not enable privileged mode or mount the Docker socket.
- **Port 6080 (noVNC):** gives full control of the browser. Bind to localhost only in dev:
  `-p 127.0.0.1:6080:6080`
- Set `VNC_PASSWORD` if exposing beyond localhost
- **Port 9222 (CDP):** no auth by default in headless mode

## Software bill of materials

[`docs/sbom.json`](docs/sbom.json) inventories the locally built container's packages in CycloneDX 1.5 format. The [SBOM workflow](.github/workflows/sbom-generation.yml) rebuilds, generates, validates, and uploads a fresh container inventory for release-branch pushes and pull requests. Its generator is pinned to the verified CycloneDX 1.5-compatible release; newer releases currently fail on this image's evidence. It does not publish images or commit generated files automatically.

The committed inventory is a build-time snapshot for its recorded architecture, not a live inventory after restart-based package upgrades. Runtime installed versions are recorded at `/usr/share/headless-chrome/packages.txt`; regenerate deployment inventories when packages change.

## Versioning

Version is read from [`VERSION`](VERSION). Current: `1.1.9` (signed package updates on startup/restart).

## Troubleshooting

**Cannot access on a remote server:** the container is likely fine — use `http://<SERVER_IP>:6080/vnc.html?...`, open firewall port 6080, and ensure `-p 6080:6080`. **TrueNAS Scale users:** you must set **Published** port 6080 in the iX App (empty `ports: []` causes connection refused). See [docs/TRUENAS_DEPLOYMENT.md](docs/TRUENAS_DEPLOYMENT.md).

**Video / streaming "Network error" or popups/extra tabs:** use LAN DNS only — primary `192.168.1.200`, secondary `192.168.1.1`. Defaults live in [`deploy/defaults.env`](deploy/defaults.env) and are baked into the image (`DNS_PRIMARY` / `DNS_SECONDARY` env). v1.1.7+ also ships deploy examples at `/opt/headless-chrome/deploy/` inside the container. **TrueNAS:** [`deploy/truenas-user_config.example.yaml`](deploy/truenas-user_config.example.yaml).

**Container restart loop / noVNC not responding:** inspect container logs and verify the installed Chromium version and host architecture before attributing a crash to a particular browser release. Test an updated image before production deployment. Do **not** mount `/config` unless ACLs allow the container `chrome` user — it causes `Permission denied` on custom entrypoints.

**Black bars on left/right in noVNC:** the virtual desktop was wider than the Chromium window. v1.1.4+ forces full-screen sizing. Rebuild, push, and redeploy if you still see them.

**Connection refused on 6080:** container is not running.

```bash
docker ps --filter name=headless-chrome
docker start headless-chrome   # if stopped
docker logs headless-chrome
```

**Blank or slow UI:** increase shared memory — `--shm-size=2g`

**Multi-platform push fails:**

```bash
docker buildx create --name multiarch --use --driver docker-container
```
