<!-- Concept: Mukesh Kesharwani -->
<!-- Contact: mukesh.kesharwani@adobe.com -->

# Browser updates and Cloudflare verification

A Cloudflare challenge failure is not proof that the browser is outdated or that bot detection was the cause. The failure page alone cannot identify the reason.

## What this project changes

- Use Debian 13 stable/security repositories for Chromium and all packaged dependencies, without an obsolete Chromium-major filter or snapshot fallback.
- Refresh signed Debian packages during bootstrap on every start/restart, then launch Chromium as a non-root user. Update failures refuse browser startup. See [runtime update requirements](RUNTIME_UPDATES.md). Rebuild periodically for base-image and Debian-release changes; Debian's supported versions may lag upstream Google Chrome.
- Keep normal GPU/software rendering available and use the configured 2 GiB shared memory rather than forcing Chromium away from `/dev/shm`.
- Preserve an isolated browser profile in the Compose `chrome-profile` volume. It contains sensitive cookies and session data; restrict access and do not commit or share it. A volume does not make verification portable between IPs or guarantee acceptance.
- Keep desktop mode as the default. The screenshot can occur in a normal desktop browser too; the project name does not imply it is running headless.

Installed package versions are recorded in `/usr/share/headless-chrome/packages.txt`. No application package manager manifests exist in this project; automation clients installed elsewhere must be upgraded and tested in their own projects.

## Refresh and test locally

```bash
docker compose build --pull --no-cache
bash scripts/test-browser.sh keekar/headless-chrome:latest
docker compose up -d
docker compose exec headless-chrome chromium --version
```

Open `http://localhost:6080/`, then navigate to the original website rather than reloading the challenge failure URL. Allow JavaScript and cookies for the website and challenge resources; interact with verification normally if requested. Do not automate challenge solving or spoof browser identity.

For a remote host, Compose now publishes noVNC only on that host's loopback address. Use an SSH tunnel or an authenticated TLS reverse proxy. Do not expose noVNC or CDP directly to the internet. Recreate the container once to adopt the bootstrap-enabled image; subsequent restarts update packages without replacing the image. Do not delete volumes to upgrade: `docker compose down -v` destroys the saved profile.

## If verification still fails

1. Confirm the running image's actual browser version and mode, rather than assuming a registry `latest` tag is current.
2. Check the container/host clock, DNS resolution, and whether the network or DNS filtering blocks the website's required Cloudflare challenge resources. Investigate specific blocked requests rather than disabling security filtering globally.
3. Try the same website in a current regular browser on the same network. Compare desktop mode without automation. VPN/proxy usage, egress-IP reputation, repeated requests, or website-specific policies may affect verification.
4. Use the website's support channel with the error code, timestamp, and Ray ID if displayed. Do not send cookies, tokens, or full browser profiles. If you own the website, use Cloudflare security events to investigate the matching request and configure narrowly scoped authorized access or a supported API for automation.

Updating dependencies and restoring browser features do not bypass Cloudflare policies or guarantee challenge success. Third-party site owners control access decisions.

## Existing security limitation

The current launcher still uses `--no-sandbox` and `--no-zygote` for its existing container deployment compatibility. Running as a non-root user and inside Docker does not replace Chromium's sandbox. This update does not establish that every TrueNAS/Docker host supports the sandbox; do not treat the container as safe for arbitrary untrusted browsing. Validate sandbox support on the deployment host and remove those flags before security-sensitive use. Protect browser-control ports with network isolation and authenticated TLS access.
