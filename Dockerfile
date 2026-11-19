FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    tigervnc-standalone-server tigervnc-tools novnc websockify \
    xfce4 xfce4-terminal dbus-x11 x11-utils xauth fonts-noto-cjk \
    python3-venv git build-essential nano ca-certificates ristretto evince python3-matplotlib python3-tk ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --shell /bin/bash --create-home --uid 1000 hellodocker
COPY --chmod=755 desktop.sh /usr/local/bin/start-desktop
WORKDIR /home/hellodocker
ENV DISPLAY=:1 MPLBACKEND=TkAgg
ARG BOARD_REV=9bbfe7a769ef66fb3d8a21b2541b3368065c958c
RUN git init /opt/helloboard && cd /opt/helloboard \
    && git remote add origin https://github.com/GCUSMS-AI-ProJect/helloboard.git \
    && git fetch --depth 1 origin "$BOARD_REV" && git checkout -b main FETCH_HEAD \
    && python3 -m venv /opt/board-venv \
    && /opt/board-venv/bin/pip install --no-cache-dir -r requirements.txt
RUN test -s /opt/helloboard/tools/bash_proxy.py
COPY --chmod=755 start.sh /usr/local/bin/start-hello
USER hellodocker
CMD ["/usr/local/bin/start-hello"]
