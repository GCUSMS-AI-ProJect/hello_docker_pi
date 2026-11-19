#!/bin/bash
set -eu
umask 077
export XDG_RUNTIME_DIR=$(mktemp -d)
config_dir="$HOME/config"
password_file="$config_dir/desktop-password"
install -d -m 700 "$config_dir"
if [ ! -e "$password_file" ] && [ -s "$HOME/desktop-password" ]; then
    mv -- "$HOME/desktop-password" "$password_file"
fi
if [ ! -s "$password_file" ]; then
    head -c 6 /dev/urandom | base64 > "$password_file"
fi
chmod 600 "$password_file"
tigervncpasswd -f < "$password_file" > "$XDG_RUNTIME_DIR/vncpass"
export XAUTHORITY="$HOME/.Xauthority"
touch "$XAUTHORITY"
xauth add "$DISPLAY" . "$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
Xtigervnc "$DISPLAY" -geometry 1440x900 -depth 24 -localhost yes -rfbport 5901 -SecurityTypes VncAuth -PasswordFile "$XDG_RUNTIME_DIR/vncpass" -auth "$XAUTHORITY" -nolisten tcp &
for attempt in {1..50}; do
    if xdpyinfo >/dev/null 2>&1; then break; fi
    sleep .1
done
xdpyinfo >/dev/null
dbus-run-session -- xfce4-session &
websockify --web=/usr/share/novnc 6080 localhost:5901 &
wait -n
