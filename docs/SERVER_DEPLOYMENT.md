<!-- Concept: Mukesh Kesharwani -->
<!-- Contact: mukesh.kesharwani@adobe.com -->

# Server deployment

How to run Headless-Chrome on a **remote server** and open it from your laptop browser.

## Automatic updates on restart

Deploy the bootstrap-enabled image once. Subsequent starts/restarts check signed Debian packages before launching the browser as `chrome`; no image rebuild is needed just to update Chromium. Bootstrap requires root initially, a writable container filesystem, and outbound HTTPS/DNS access to official Debian repositories. Allow an eleven-minute startup health-check grace period. Updates fail closed; `CHROME_AUTO_UPDATE=0` is an explicit offline/non-root opt-out. See [runtime update requirements](RUNTIME_UPDATES.md).

## Your logs look healthy

Messages like these are **warnings**, not failures:

| Log line | Meaning |
| ---------- | --------- |
| `_XSERVTransmkdir: euid != 0` | Fixed in v1.1.1+ (pre-creates `/tmp/.X11-unix`) |
| `Openbox-Message: Unable to find ... menu` | Fixed in v1.1.1+ (minimal menu added) |
| `dbus ... Failed to connect` | Normal in Docker; Chromium still runs |
| `listen6: bind: Address already in use` | x11vnc uses IPv4 only; harmless |
| `Desktop Chrome is ready` | **Container started successfully** |
| `Listen on :6080` / `proxying from :6080` | noVNC is running |

If you see those lines, the problem is almost always **network access**, not Chrome failing to start.

## Critical: do not use localhost from your laptop

Inside the container, logs say `http://localhost:6080` — that only works **on the server itself**.

From your laptop, use:

```text
http://<SERVER_PUBLIC_IP_OR_DNS>:6080/vnc.html?autoconnect=1&resize=scale
```

Example:

```text
http://203.0.113.10:6080/vnc.html?autoconnect=1&resize=scale
```

## Server checklist

### 1. Publish port 6080

```bash
docker run -d --restart unless-stopped \
  --name headless-chrome \
  -p 6080:6080 \
  --shm-size=2g \
  --dns 192.168.1.200 \
  --dns 192.168.1.1 \
  -e VNC_PASSWORD='choose-a-strong-password' \
  keekar/headless-chrome:latest
```

See [`deploy/docker-run.example.sh`](../deploy/docker-run.example.sh), [`deploy/defaults.env`](../deploy/defaults.env), and [`docker-compose.yml`](../docker-compose.yml) for the same DNS defaults (bundled in image v1.1.7+ at `/opt/headless-chrome/deploy/`).

Verify on the **server**:

```bash
curl -I http://127.0.0.1:6080/vnc.html
# Expect: HTTP/1.1 200
```

### 2. Open firewall / security group

Allow **inbound TCP 6080** from your IP (or VPN):

- **AWS:** Security Group → Inbound → TCP 6080
- **GCP:** VPC firewall rule → tcp:6080
- **Azure:** NSG → Allow 6080
- **Linux ufw:** `sudo ufw allow 6080/tcp`

### 3. Confirm Docker published the port

```bash
docker ps --filter name=headless-chrome
# PORTS should show: 0.0.0.0:6080->6080/tcp
```

### 4. Test from your laptop

```bash
curl -I http://<SERVER_IP>:6080/vnc.html
```

If this fails but step 1 works on the server → firewall or cloud security group is blocking you.

## Kubernetes / ECS / Nomad

Expose container port **6080** on a LoadBalancer or NodePort Service. Do not assume ClusterIP is reachable from outside the cluster.

Example Kubernetes Service (NodePort):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: headless-chrome
spec:
  type: NodePort
  selector:
    app: headless-chrome
  ports:
    - port: 6080
      targetPort: 6080
      nodePort: 30080
```

Then open: `http://<node-ip>:30080/vnc.html?autoconnect=1&resize=scale`

## Security on public servers

Always set a password when exposing beyond localhost:

```bash
-e VNC_PASSWORD='your-secret-password'
```

Prefer:

- VPN or private subnet only
- Restrict firewall to your office/home IP
- Reverse proxy with HTTPS + auth (nginx, Caddy, Traefik)

## Troubleshooting commands (run on server)

```bash
# Container running?
docker ps -a --filter name=headless-chrome

# Logs
docker logs headless-chrome --tail 50

# Port listening on host?
ss -tlnp | grep 6080

# Health
docker inspect --format='{{.State.Health.Status}}' headless-chrome
```

## Rebuild after fixes

Pull or rebuild v1.1.1+ for X11/openbox/websockify binding fixes:

```bash
DOCKERHUB_PUSH=0 ./scripts/build-and-push-dockerhub.sh
# or after push to Hub:
docker pull keekar/headless-chrome:latest
docker stop headless-chrome && docker rm headless-chrome
# re-run docker run ...
```
