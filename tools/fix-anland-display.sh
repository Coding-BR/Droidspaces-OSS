#!/system/bin/sh
set -eu

DROIDSPACES="${DROIDSPACES:-/data/local/Droidspaces/bin/droidspaces}"
CONTAINER="${CONTAINER:-Ubuntu}"
CONFIG="${CONFIG:-/data/local/Droidspaces/Containers/$CONTAINER/container.config}"
ENVFILE="${ENVFILE:-/data/local/Droidspaces/Containers/$CONTAINER/anland.env}"
ANLAND_SOCKET_HOST="${ANLAND_SOCKET_HOST:-/data/local/tmp/display_daemon.sock}"
ANLAND_DAEMON="${ANLAND_DAEMON:-}"
ANLAND_APK="${ANLAND_APK:-}"
ANLAND_FORCE_REINSTALL="${ANLAND_FORCE_REINSTALL:-0}"
ANLAND_PACKAGE="${ANLAND_PACKAGE:-com.anland.consumer}"
ANLAND_LOG="${ANLAND_LOG:-/data/local/tmp/display_daemon.log}"

die() {
  echo "[ERRO] $*" >&2
  exit 1
}

find_first_file() {
  for path in "$@"; do
    [ -f "$path" ] && {
      echo "$path"
      return 0
    }
  done
  return 1
}

stop_daemons() {
  for pid in $(pidof display_daemon display_daemon_patched 2>/dev/null || true); do
    kill -9 "$pid" 2>/dev/null || true
  done
}

[ "$(id -u)" = "0" ] || die "execute como root via su"
[ -x "$DROIDSPACES" ] || die "Droidspaces nao encontrado: $DROIDSPACES"
[ -f "$CONFIG" ] || die "Config nao encontrada: $CONFIG"

if [ -z "$ANLAND_DAEMON" ]; then
  ANLAND_DAEMON="$(find_first_file \
    /data/local/tmp/display_daemon_patched \
    /data/adb/modules/anland-daemon/display_daemon \
    /sdcard/Download/WayLandIE/anland/magisk_module/display_daemon \
    /sdcard/Download/WayLandIE/anland/build_daemon_android/display_daemon \
    /data/local/tmp/display_daemon \
  )" || die "display_daemon nao encontrado. Defina ANLAND_DAEMON=/caminho/display_daemon"
fi

if [ -z "$ANLAND_APK" ]; then
  ANLAND_APK="$(find_first_file \
    /sdcard/Download/sistemas/aland/app-debug.apk \
    /sdcard/Download/WayLandIE/anland/consumers/anland/android_consumer/app/build/outputs/apk/debug/app-debug.apk \
  )" || true
fi

echo "[1/8] Parando container, app Anland e daemons antigos..."
"$DROIDSPACES" --name="$CONTAINER" stop >/dev/null 2>&1 || "$DROIDSPACES" stop "$CONTAINER" >/dev/null 2>&1 || true
am force-stop "$ANLAND_PACKAGE" >/dev/null 2>&1 || true
stop_daemons
rm -f "$ANLAND_SOCKET_HOST" "$ANLAND_LOG"

if [ -n "$ANLAND_APK" ]; then
  if ! cmd package path "$ANLAND_PACKAGE" >/dev/null 2>&1 || [ "$ANLAND_FORCE_REINSTALL" = "1" ]; then
    echo "[2/8] Instalando APK Anland compatível..."
    pm uninstall "$ANLAND_PACKAGE" >/dev/null 2>&1 || true
    pm install -t "$ANLAND_APK" >/dev/null || die "falha ao instalar $ANLAND_APK"
  else
    echo "[2/8] APK Anland já instalado. Use ANLAND_FORCE_REINSTALL=1 para reinstalar."
  fi
else
  echo "[2/8] APK Anland nao informado/encontrado; mantendo instalacao atual."
fi

echo "[3/8] Criando env_file Anland..."
cat >/data/local/tmp/anland.env <<'EOF'
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
WAYLAND_DISPLAY=wayland-0
XDG_SESSION_TYPE=wayland
QT_QPA_PLATFORM=wayland
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
TU_DEBUG=noconform
XCURSOR_SIZE=48
PULSE_SERVER=unix:/tmp/.pulse-socket
EOF
cat /data/local/tmp/anland.env >"$ENVFILE"
chmod 0644 "$ENVFILE"

echo "[4/8] Ajustando container.config para Anland..."
tmp_config=/data/local/tmp/container.config.anland
sed '/^enable_termux_x11=/d;/^enable_hw_access=/d;/^enable_gpu_mode=/d;/^env_file=/d;/^bind_mounts=/d' "$CONFIG" >"$tmp_config"
{
  echo "enable_termux_x11=0"
  echo "enable_hw_access=1"
  echo "enable_gpu_mode=1"
  echo "env_file=$ENVFILE"
  echo "bind_mounts=$ANLAND_SOCKET_HOST:/run/display.sock"
} >>"$tmp_config"
cp "$tmp_config" "$CONFIG"
chmod 0666 "$CONFIG" || true

echo "[5/8] Iniciando daemon Anland antes do container..."
chmod 0755 "$ANLAND_DAEMON"
"$ANLAND_DAEMON" "$ANLAND_SOCKET_HOST" >"$ANLAND_LOG" 2>&1 &
sleep 1
[ -S "$ANLAND_SOCKET_HOST" ] || die "daemon nao criou socket: $ANLAND_SOCKET_HOST"
chmod 0777 "$ANLAND_SOCKET_HOST" || true
ls -li "$ANLAND_SOCKET_HOST"

echo "[6/8] Abrindo consumidor Anland..."
monkey -p "$ANLAND_PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 3

echo "[7/8] Iniciando container com bind mount do socket atual..."
"$DROIDSPACES" --name="$CONTAINER" --conf="$CONFIG" start
"$DROIDSPACES" --name="$CONTAINER" run sh -lc '
  rm -rf /tmp/.X11-unix /tmp/.ICE-unix /run/user/0
  mkdir -p /tmp/.X11-unix /tmp/.ICE-unix /run/user/0
  chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix
  chmod 700 /run/user/0
  cat >/etc/environment <<EOF
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
WAYLAND_DISPLAY=wayland-0
XDG_SESSION_TYPE=wayland
QT_QPA_PLATFORM=wayland
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
TU_DEBUG=noconform
XCURSOR_SIZE=48
PULSE_SERVER=unix:/tmp/.pulse-socket
EOF'

echo "[8/8] Subindo KDE/Anland..."
"$DROIDSPACES" --name="$CONTAINER" run sh -lc \
  'pkill -9 kwin_wayland plasmashell Xwayland 2>/dev/null || true;
   nohup /usr/local/bin/startanland-kde.sh >/tmp/anland-kde.log 2>&1 &'
sleep 5

echo
echo "[OK] Estado atual:"
cat "$ANLAND_LOG" 2>/dev/null || true
"$DROIDSPACES" --name="$CONTAINER" run sh -lc \
  'stat -c "socket inode=%i mode=%A" /run/display.sock 2>/dev/null || true;
   printenv ANLAND ANLAND_SOCKET WAYLAND_DISPLAY PULSE_SERVER;
   ps -ef | grep -E "kwin_wayland|plasmashell|Xwayland" | grep -v grep || true;
   tail -60 /tmp/anland-kde.log 2>/dev/null | grep -Ei "anland|fallback|MESA|EGL|failed|dmabuf|consumer" || true'
