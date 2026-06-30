#!/system/bin/sh
set -e

# Build directory inside container rootfs on host
BUILD_DIR="/mnt/Droidspaces/Ubuntu/root/pulseaudio_build"
TERMUX_DIR="/data/data/com.termux/files"
TARGET_DIR="/data/local/Droidspaces/usr"

echo "[1/3] Preparando diretório de build e copiando arquivos do Termux..."
mkdir -p "$BUILD_DIR/bin"
mkdir -p "$BUILD_DIR/lib"
mkdir -p "$BUILD_DIR/etc"

cp "$TERMUX_DIR/usr/bin/pulseaudio" "$BUILD_DIR/bin/"
cp "$TERMUX_DIR/usr/bin/pactl" "$BUILD_DIR/bin/"
cp -r "$TERMUX_DIR/usr/lib/pulseaudio" "$BUILD_DIR/lib/"
cp -r "$TERMUX_DIR/usr/etc/pulse" "$BUILD_DIR/etc/"

LIBS="libpulse.so libltdl.so libdbus-1.so libsndfile.so libsoxr.so libspeexdsp.so libiconv.so libandroid-execinfo.so libFLAC.so libvorbis.so libvorbisenc.so libopus.so libogg.so libmp3lame.so"
for LIB in $LIBS; do
  cp "$TERMUX_DIR/usr/lib/$LIB" "$BUILD_DIR/lib/"
done

echo "[2/3] Aplicando patches binários no contêiner..."
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run python3 /root/patch_binaries.py "/root/pulseaudio_build/bin/pulseaudio"
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run python3 /root/patch_binaries.py "/root/pulseaudio_build/bin/pactl"
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run python3 /root/patch_binaries.py "/root/pulseaudio_build/lib/libpulse.so"
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run python3 /root/patch_binaries.py "/root/pulseaudio_build/lib/pulseaudio/libpulsecore-17.0.so"
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run python3 /root/patch_binaries.py "/root/pulseaudio_build/lib/pulseaudio/libpulsecommon-17.0.so"

/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run sh -c 'for MOD in /root/pulseaudio_build/lib/pulseaudio/modules/*.so; do python3 /root/patch_binaries.py "$MOD"; done'

echo "[3/3] Movendo arquivos patcheados para o destino e limpando..."
mkdir -p "$TARGET_DIR"
rm -f "$TARGET_DIR/usr"
ln -sf . "$TARGET_DIR/usr"

cp -r "$BUILD_DIR"/* "$TARGET_DIR/"
rm -rf "$BUILD_DIR"

echo "[OK] PulseAudio successfully ported to Droidspaces path!"
