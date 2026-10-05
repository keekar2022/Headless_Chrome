<!-- Concept: Mukesh Kesharwani -->
<!-- Contact: mukesh.kesharwani@adobe.com -->

# Signed browser updates at startup and restart

## One-time adoption

Build and deploy the bootstrap-enabled image once. Restarting an old image cannot add this feature. For local Compose:

```bash
docker compose build --pull --no-cache
docker compose up -d --force-recreate
```

For a remote Docker or TrueNAS deployment, publish the updated image using the existing build script, then pull and recreate/redeploy the container once. This repository change alone does not publish anything to Docker Hub. Retain the browser-profile volume when redeploying.

## Normal operation

```bash
docker restart headless-chrome
docker logs --tail 80 headless-chrome
docker exec headless-chrome chromium --version
```

Wait for the signed-update completion and browser-ready messages before checking the version. `docker restart` waits for the container process to start, not for bootstrap or browser readiness.

Each start/restart performs this sequence:

1. Validate `CHROME_AUTO_UPDATE` (only `1` or `0` is accepted).
2. With updates enabled, run a bounded root bootstrap. Refresh metadata from the image's official Debian stable/security repositories over HTTPS. APT verifies Debian signatures and metadata validity; repository errors are fatal, and unauthenticated/insecure repositories are not accepted.
3. Upgrade installed packages, including browser dependencies and desktop libraries. Package removals are forbidden. Verify Chromium, chromium-common, and chromium-sandbox match the repository candidates and that the package database has no pending problems.
4. Refresh `/usr/share/headless-chrome/packages.txt` atomically.
5. Drop to `chrome`, clear capabilities, enable no-new-privileges, and execute the existing browser launcher. Neither Chromium nor noVNC runs as root in the default deployment.

If no newer packages are available, APT leaves installed versions unchanged. Updates happen before the browser runs, never during an active session. Future restart checks fetch fresh metadata instead of relying on cached candidates. These are current supported Debian Chromium packages, not a guarantee of the newest upstream Google Chrome release.

## Deployment requirements

- Allow the image's root bootstrap. Do not force a non-root container user with automatic updates enabled. No privileged mode, Docker socket, or host package access is required.
- Keep the container root filesystem writable for APT and dpkg. Do not mount host package databases, `/usr`, or `/var/lib/dpkg` into the container.
- Permit DNS and outbound HTTPS access to official Debian repositories. Keep the host clock accurate for TLS and repository-validity checks.
- Allow up to ten minutes for the update operation, plus termination/startup time. The image health check has an eleven-minute startup grace period; align custom TrueNAS/orchestrator readiness settings accordingly. Unhealthy status by itself does not make standalone Docker restart a running container.
- Package changes persist in the container's writable layer across restarts, but disappear when it is recreated. Bootstrap applies current updates again to a fresh container. Browser-profile persistence is separate.
- Continue periodic image maintenance for project changes, Debian major-release migrations, archive-key changes that cannot be resolved with the existing trust chain, and transitions requiring package removals. Runtime updates are not a substitute for image rollback or backup planning.

## Failure and offline policy

Repository, signature, TLS, installation, candidate-version, or timeout failures exit nonzero before starting the browser. The previous browser is not silently launched. With `restart: unless-stopped`, an extended repository outage can cause repeated startup failures; stop the container while investigating if needed.

An interrupted installation may leave dpkg requiring repair. Do not launch the browser from that state. Prefer recreating from a known-good image while preserving profile storage, then retry signed updates. No automatic signature bypass, untrusted fallback repository, or forced package removal is used.

For an intentional offline or forced-non-root deployment, set `CHROME_AUTO_UPDATE=0` and recreate the container so the new environment takes effect. For Compose:

```bash
CHROME_AUTO_UPDATE=0 docker compose up -d --force-recreate
```

This explicitly opts out of freshness checks and uses installed packages; browser patching then requires normal image maintenance. A root bootstrap with updates disabled still drops to `chrome`. A forced non-root deployment must have appropriate profile/runtime-directory permissions.

## Verification

```bash
bash scripts/test-browser.sh keekar/headless-chrome:latest
```

The test checks desktop and headless startup/restart, successful update completion twice in the same container, non-root browser processes, no-new-privileges, explicit offline mode, and refusal to start for invalid settings, insufficient privileges, inaccessible repositories, and an unsigned test repository. Failure-only test tools in disposable containers also exercise timeout and candidate-version mismatch handling; no test tools are included in the shipped image. Tests use temporary containers and loopback-only control ports. They do not attempt to solve Cloudflare challenges.
