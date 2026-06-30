#!/bin/bash
# Script para compilar o PulseAudio nativo para Android (AArch64) usando o NDK
# Este script baixa as fontes, configura e compila o PulseAudio de forma estática

set -e

# Configurações do NDK
NDK_VERSION="27.3.13750724"
ANDROID_NDK_HOME="${ANDROID_SDK_ROOT:-/c/Users/adriano/AppData/Local/Android/Sdk}/ndk/$NDK_VERSION"
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64"
API=29

# Configura compiladores do NDK
export CC="$TOOLCHAIN/bin/aarch64-linux-android$API-clang"
export CXX="$TOOLCHAIN/bin/aarch64-linux-android$API-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export LD="$TOOLCHAIN/bin/llvm-ld"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"

# Pastas de build
WORK_DIR=$(pwd)/build_pa
INSTALL_DIR=$(pwd)/assets/pulseaudio-aarch64

mkdir -p "$WORK_DIR"
mkdir -p "$INSTALL_DIR"

echo "=== 1. Baixando e compilando libltdl (libtool) ==="
cd "$WORK_DIR"
if [ ! -d "libtool-2.4.7" ]; then
    curl -L -o libtool-2.4.7.tar.gz https://ftpmirror.gnu.org/libtool/libtool-2.4.7.tar.gz
    tar -xf libtool-2.4.7.tar.gz
fi
cd libtool-2.4.7
./configure --host=aarch64-linux-android --prefix="$INSTALL_DIR" --enable-static --disable-shared
make -j$(nproc)
make install

echo "=== 2. Baixando e compilando libsndfile ==="
cd "$WORK_DIR"
if [ ! -d "libsndfile-1.2.2" ]; then
    curl -L -o libsndfile-1.2.2.tar.xz https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz
    tar -xf libsndfile-1.2.2.tar.xz
fi
cd libsndfile-1.2.2
./configure --host=aarch64-linux-android --prefix="$INSTALL_DIR" --enable-static --disable-shared --disable-external-libs
make -j$(nproc)
make install

echo "=== 3. Baixando e compilando PulseAudio com OpenSL ES ==="
cd "$WORK_DIR"
if [ ! -d "pulseaudio-17.0" ]; then
    curl -L -o pulseaudio-17.0.tar.xz https://freedesktop.org/software/pulseaudio/releases/pulseaudio-17.0.tar.xz
    tar -xf pulseaudio-17.0.tar.xz
fi
cd pulseaudio-17.0

# Exporta variáveis de dependências locais
export LTDL_CFLAGS="-I$INSTALL_DIR/include"
export LTDL_LIBS="-L$INSTALL_DIR/lib -lltdl"
export SNDFILE_CFLAGS="-I$INSTALL_DIR/include"
export SNDFILE_LIBS="-L$INSTALL_DIR/lib -lsndfile"

# Configura o PulseAudio
./configure \
  --host=aarch64-linux-android \
  --prefix="$INSTALL_DIR" \
  --enable-static-bins \
  --disable-shared \
  --enable-static \
  --disable-alsa \
  --disable-x11 \
  --disable-dbus \
  --disable-glib \
  --disable-oss \
  --disable-udev \
  --disable-bluez5 \
  --disable-avahi \
  --disable-jack \
  --enable-opensles \
  --with-database=simple

make -j$(nproc)
make install

echo "=== COMPILAÇÃO CONCLUÍDA COM SUCESSO! ==="
echo "Os binários e módulos estão em: $INSTALL_DIR"
