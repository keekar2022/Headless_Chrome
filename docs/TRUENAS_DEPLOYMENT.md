<!-- Concept: Mukesh Kesharwani -->
<!-- Contact: mukesh.kesharwani@adobe.com -->

# TrueNAS Scale deployment (ix-app)

This image works on **TrueNAS Scale** using the **iX App** (custom container) wizard. The container itself was healthy on `nas.keekar.au`; access failed because **host port 6080 was not published**.

## Bootstrap-enabled image requirements

Pull and redeploy the updated image once; restarting an older image does not add automatic updates. Leave the image's initial root user unchanged and the container root filesystem writable. Bootstrap upgrades signed Debian packages over HTTPS on each subsequent start/restart, then launches Chromium and desktop services as `chrome`. Keep privileged mode disabled; do not mount a Docker socket. Permit official Debian repository DNS/HTTPS access and allow the image's eleven-minute startup health-check grace period. If TrueNAS forces a non-root user or an offline/read-only deployment is required, explicitly set `CHROME_AUTO_UPDATE=0` and maintain packages through rebuilt images instead. See [runtime update requirements](RUNTIME_UPDATES.md).

## Root cause (confirmed on nas.keekar.au)

| Check | Before fix | After fix |
| ------- | ------------ | ----------- |
| Container status | `healthy` | `healthy` |
| noVNC inside container | `HTTP 200` on `172.16.4.2:6080` | OK |
| Docker `PortBindings` | `{}` (empty) | `6080:6080` published |
| `docker ps` PORTS | `6080/tcp` only | `0.0.0.0:6080->6080/tcp` |
| External access | `Connection refused` | `HTTP 200` |

TrueNAS **portals do not publish ports**. You must add an explicit **Published** port in the app config. If `ports: []`, the portal entry is ignored by the ix-app renderer.

## Required TrueNAS settings

In **Apps → chrome → Edit** (iX App):

### 1. Publish port 6080 (required)

| Field | Value |
| ------- | ------- |
| Container Port | `6080` |
| Host Port | `6080` (or any free port) |
| Bind Mode | **Published** |
| Protocol | TCP |

This must produce config like:

```yaml
"ports":
  - "bind_mode": "published"
    "container_port": 6080
    "host_ips": []
    "port_number": 6080
    "protocol": "tcp"
```

See [`deploy/truenas-user_config.example.yaml`](../deploy/truenas-user_config.example.yaml) and [`deploy/truenas-ports.example.yaml`](../deploy/truenas-ports.example.yaml).

### 2. Portal (optional but recommended)

| Field | Value |
| ------- | ------- |
| Name | Web UI |
| Scheme | http |
| Path | `/vnc.html` |
| Port | `6080` |
| Use Node IP | enabled |

### 3. Custom DNS (required for YouTube / streaming)

Video **"Network error! Please reload the page and play video again"** was traced to **bad DNS inside the container**:

| Problem | Symptom | Fix |
| --------- | --------- | ----- |
| Search domain `keekar.com` | `ytimg.com` → `ytimg.com.keekar.com` (wrong IP) | Set `searches: []` and `dns_search: ["."]` |
| Secondary `192.168.1.1` | pfSense DNS **times out** from Docker bridge | Use **only** `192.168.1.200` |
| Public DNS (`1.1.1.1`) | Bypasses AdGuard; ads/popups | Do not use |

**Apps → chrome → Edit → Custom DNS Setup:**

| Setting | Value |
| --------- | ------- |
| Nameserver | `192.168.1.200` only |
| Search domains | *(empty / none)* |
| DNS option | `ndots:2` |

```yaml
"dns_config":
  "nameservers":
    - "192.168.1.200"
  "searches": []
  "options":
    - "name": "ndots"
      "value": "2"
```

If TrueNAS UI does not apply changes, patch rendered compose and restart:

```bash
# Edit user_config.yaml as above, redeploy, then verify:
sudo docker inspect ix-chrome-chrome-1 --format '{{json .HostConfig.Dns}}'
# Expect: ["192.168.1.200"]

sudo docker exec ix-chrome-chrome-1 cat /etc/resolv.conf
# Expect: ExtServers: [192.168.1.200] and NO "search keekar.com"

sudo docker exec ix-chrome-chrome-1 getent hosts ytimg.com
# Expect: no output (not ytimg.com.keekar.com)

sudo docker exec ix-chrome-chrome-1 getent ahostsv4 i.ytimg.com | head -1
# Expect: Google CDN IPv4 (e.g. 192.178.x.x)
```

See [`deploy/truenas-user_config.example.yaml`](../deploy/truenas-user_config.example.yaml).

### 4. Do not mount `/config` unless needed

The image uses an isolated profile at `/tmp/chrome-profile`. A leftover mount from another app (e.g. `firefox` appdata) is unnecessary unless you intentionally persist data.

### 5. Recommended resources

- **Shared memory:** add `--shm-size=2g` equivalent if the ix-app exposes it, or ensure adequate container memory
- **Image:** `keekar/headless-chrome:latest` (v1.1.7+ bundles LAN DNS defaults in image ENV and `/opt/headless-chrome/deploy/`)
- **Platform:** `linux/amd64` on x86_64 NAS

## Access URL

After port 6080 is published:

```text
http://nas.keekar.au:6080/
```

The root URL auto-redirects to the noVNC client with auto-connect and scaled display (no directory listing).

## Verify on the NAS (SSH)

```bash
# Port must show host mapping, not just 6080/tcp
sudo docker ps --filter name=ix-chrome --format '{{.Ports}}'
# Expected: 0.0.0.0:6080->6080/tcp

# From NAS
curl -I http://127.0.0.1:6080/vnc.html

# From your laptop
curl -I http://nas.keekar.au:6080/vnc.html
```

## Apply config via CLI (admin)

If the UI keeps clearing ports, patch `user_config.yaml` and redeploy:

```bash
# Edit /mnt/.ix-apps/app_configs/chrome/versions/<version>/user_config.yaml
# Set ports section as above, then:
midclt call app.redeploy chrome
```

## Logs that look scary but are OK

- `_XSERVTransmkdir: euid != 0` — fixed in image v1.1.1+
- `dbus ... Failed to connect` — normal in containers
- `Openbox-Message: Unable to find menu` — fixed in v1.1.1+

If you see **`Desktop Chrome is ready`** and **`Listen on :6080`**, the image is running; check port publishing next.
