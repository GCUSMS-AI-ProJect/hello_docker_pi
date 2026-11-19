FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    tigervnc-standalone-server tigervnc-tools novnc websockify \
    xfce4 xfce4-terminal dbus-x11 x11-utils xauth fonts-noto-cjk \
    python3-venv git build-essential nano ca-certificates ristretto evince python3-matplotlib python3-tk ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --shell /bin/bash --create-home --uid 1000 hellodocker
COPY --chmod=755 desktop.sh /usr/local/bin/start-desktop
USER hellodocker
WORKDIR /home/hellodocker
ENV DISPLAY=:1 MPLBACKEND=TkAgg
CMD ["/usr/local/bin/start-desktop"]

USER root
ARG BOARD_REV=96bf9ca5c860ce153b41fb2c89355df9ef45146e
RUN git init /opt/helloboard && cd /opt/helloboard \
    && git remote add origin https://github.com/GCUSMS-AI-ProJect/helloboard.git \
    && git fetch --depth 1 origin "$BOARD_REV" && git checkout -b main FETCH_HEAD \
    && python3 -m venv /opt/board-venv \
    && /opt/board-venv/bin/pip install --no-cache-dir -r requirements.txt
COPY --chmod=755 start.sh /usr/local/bin/start-hello
USER hellodocker
CMD ["/usr/local/bin/start-hello"]
