FROM node:22-bookworm-slim

# Pin the same CLI version used for local command/feature checks. npm selects
# the official Linux arm64 or amd64 native package for the build platform.
RUN npm install --global --no-audit --no-fund @openai/codex@0.162.1 \
    && codex --version

WORKDIR /opt/personal-os/gateway
COPY gateway/ ./
COPY web/ /opt/personal-os/web/
RUN mkdir -p /var/lib/personal-os /home/node/.codex \
    && chown node:node /var/lib/personal-os /home/node/.codex \
    && chmod 700 /var/lib/personal-os /home/node/.codex

ENV PERSONAL_OS_PROFILE=/var/lib/personal-os \
    PERSONAL_OS_WEB_ROOT=/opt/personal-os/web \
    PERSONAL_OS_OPEN_BROWSER=0 \
    PERSONAL_OS_PORT=8787 \
    PERSONAL_OS_PROVIDER=codex-cli
USER node
CMD ["node", "server.mjs"]
