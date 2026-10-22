FROM debian:bookworm-slim
ARG GODOT_VERSION=4.6
# Godot's official runtime is obtained directly from the official release.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 libgl1 libasound2 libpulse0 libudev1 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip \
 && unzip /tmp/godot.zip -d /usr/local/bin && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot && rm /tmp/godot.zip \
 && chmod +x /usr/local/bin/godot
COPY runtime /srv/game
RUN useradd --uid 10002 --create-home game && chown -R game:game /srv/game
USER game
EXPOSE 9080
WORKDIR /srv/game
ENTRYPOINT ["godot", "--headless", "--path", "/srv/game", "--", "--aoem-server"]
