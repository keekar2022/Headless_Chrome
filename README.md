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
docker run --rm -d -p 6080:6080 --shm-size=2g --name headless-chrome keekar/headless-chrome:latest
```

Open in **any browser**:

**http://localhost:6080/**

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

### Update Chromium / noVNC

Chromium and noVNC come from Debian packages at **build time**. To refresh them:

1. Bump [`VERSION`](VERSION) (e.g. `1.1.4`)
2. Run `./scripts/build-and-push-dockerhub.sh`

The build script uses **`--no-cache` by default**, so each run re-runs `apt-get` and pulls current package versions. No extra flags needed.

On the server: pull and redeploy (`docker pull keekar/headless-chrome:latest`, then redeploy the app).

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_BUILD_CACHE` | `0` | Set to `1` for faster builds using Docker layer cache (may skip fresh apt packages) |
| `DOCKERHUB_PUSH` | `1` | Set to `0` for local build only |
| `DOCKERHUB_USERNAME` | `keekar` | Docker Hub namespace |
| `CHROME_MODE` | `desktop` | `desktop` = visible Chrome via noVNC; `headless` = CDP only |
| `NOVNC_PORT` | `6080` | Web UI port for desktop mode |
| `START_URL` | `about:blank` | URL Chromium opens on start |
| `VNC_PASSWORD` | (none) | **Set on public servers** — VNC/noVNC password |
| `NOVNC_LISTEN` | `0.0.0.0` | Address noVNC binds to inside the container |
| `CHROME_PROFILE` | `/tmp/chrome-profile` | Isolated profile dir inside container |
| `CHROME_PORT` | `9222` | CDP port (headless mode only) |

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

- **Port 6080 (noVNC):** gives full control of the browser. Bind to localhost only in dev:
  `-p 127.0.0.1:6080:6080`
- Set `VNC_PASSWORD` if exposing beyond localhost
- **Port 9222 (CDP):** no auth by default in headless mode

## Versioning

Version is read from [`VERSION`](VERSION). Current: `1.1.0` (desktop/noVNC mode).

## Troubleshooting

**Cannot access on a remote server:** the container is likely fine — use `http://<SERVER_IP>:6080/vnc.html?...`, open firewall port 6080, and ensure `-p 6080:6080`. **TrueNAS Scale users:** you must set **Published** port 6080 in the iX App (empty `ports: []` causes connection refused). See [docs/TRUENAS_DEPLOYMENT.md](docs/TRUENAS_DEPLOYMENT.md).

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
