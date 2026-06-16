# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
#
# Isolated Chromium in Docker with a normal window via noVNC (default),
# or headless CDP mode when CHROME_MODE=headless.

FROM debian:bookworm-slim

ENV CHROME_MODE=desktop \
    NOVNC_PORT=6080 \
    NOVNC_LISTEN=0.0.0.0 \
    VNC_PORT=5900 \
    START_URL=about:blank \
    CHROME_PORT=9222 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        chromium \
        curl \
        dbus-x11 \
        fonts-liberation \
        novnc \
        openbox \
        socat \
        websockify \
        x11vnc \
        xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system chrome \
    && useradd --system --gid chrome --home-dir /home/chrome --create-home chrome \
    && mkdir -p /tmp/.X11-unix /tmp/chrome-profile /tmp/runtime-chrome \
    && chmod 1777 /tmp/.X11-unix \
    && chown -R chrome:chrome /tmp/chrome-profile /tmp/runtime-chrome /home/chrome

COPY scripts/openbox/debian-menu.xml /var/lib/openbox/debian-menu.xml
COPY scripts/novnc/index.html /usr/share/novnc/index.html
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER chrome
WORKDIR /home/chrome

EXPOSE 6080 9222

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD sh -c 'if [ "$CHROME_MODE" = "headless" ] || [ "$CHROME_MODE" = "cdp" ]; then curl -sf "http://127.0.0.1:${CHROME_PORT}/json/version"; else curl -sf "http://127.0.0.1:${NOVNC_PORT}/"; fi' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
