# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
#
# Isolated Chromium in Docker with a normal window via noVNC (default),
# or headless CDP mode when CHROME_MODE=headless.

FROM debian:trixie-slim

ARG VERSION=dev
ARG BUILD_DATE

LABEL org.opencontainers.image.title="headless-chrome" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.description="Isolated Chromium desktop via noVNC or headless CDP"

ENV CHROME_MODE=desktop \
    CHROME_AUTO_UPDATE=1 \
    NOVNC_PORT=6080 \
    NOVNC_LISTEN=0.0.0.0 \
    VNC_PORT=5900 \
    START_URL=about:blank \
    CHROME_PORT=9222 \
    DNS_PRIMARY=192.168.1.200 \
    DNS_SECONDARY=192.168.1.1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        chromium \
        chromium-sandbox \
        curl \
        dbus-x11 \
        fonts-liberation \
        novnc \
        openbox \
        socat \
        util-linux \
        websockify \
        wmctrl \
        x11vnc \
        xvfb \
    && sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && mkdir -p /usr/share/headless-chrome \
    && dpkg-query -W -f='${Package}\t${Version}\n' > /usr/share/headless-chrome/packages.txt \
    && chromium --version \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system chrome \
    && useradd --system --gid chrome --home-dir /home/chrome --create-home chrome \
    && mkdir -p /tmp/.X11-unix /tmp/chrome-profile /tmp/runtime-chrome /home/chrome/.config/openbox \
    && chmod 1777 /tmp/.X11-unix \
    && chown -R chrome:chrome /tmp/chrome-profile /tmp/runtime-chrome /home/chrome

COPY scripts/openbox/debian-menu.xml /var/lib/openbox/debian-menu.xml
COPY scripts/openbox/rc.xml /home/chrome/.config/openbox/rc.xml
RUN chown chrome:chrome /home/chrome/.config/openbox/rc.xml
COPY scripts/novnc/index.html /usr/share/novnc/index.html
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/bootstrap.sh /usr/local/bin/bootstrap.sh
COPY scripts/update-browser.sh /usr/local/bin/update-browser.sh
COPY deploy/ /opt/headless-chrome/deploy/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/bootstrap.sh /usr/local/bin/update-browser.sh /opt/headless-chrome/deploy/docker-run.example.sh

# Bootstrap installs signed updates as root, then execs the launcher as chrome.
USER root
WORKDIR /home/chrome

EXPOSE 6080 9222

HEALTHCHECK --interval=30s --timeout=5s --start-period=11m --retries=3 \
    CMD sh -c 'if [ "$CHROME_MODE" = "headless" ] || [ "$CHROME_MODE" = "cdp" ]; then curl -sf "http://127.0.0.1:${CHROME_PORT}/json/version"; else curl -sf "http://127.0.0.1:${NOVNC_PORT}/"; fi' || exit 1

ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]
