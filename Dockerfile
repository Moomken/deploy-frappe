FROM frappe/bench:latest

USER root

# 1. Install all system deps (including supervisor & pipx) at build-time:
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git python3-pip pipx python3-dev python3-setuptools python3-venv virtualenv \
      nodejs npm xvfb libfontconfig wkhtmltopdf supervisor && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

# 2. As 'frappe' user, install bench CLI and honcho via pipx:
USER frappe
RUN pipx ensurepath && \
    pipx install --force frappe-bench && \
    pipx install --force honcho

# 3. Copy your init script in place:
USER root
COPY init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

ENTRYPOINT ["bash", "/usr/local/bin/init.sh"]
