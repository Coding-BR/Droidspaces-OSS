#!/system/bin/sh
set -e

# Extract source
rm -rf /mnt/Droidspaces/Ubuntu/root/droidspaces-build
mkdir -p /mnt/Droidspaces/Ubuntu/root/droidspaces-build
tar -xzf /data/local/tmp/Droidspaces-src.tar.gz -C /mnt/Droidspaces/Ubuntu/root/droidspaces-build

# Run build inside container (target: droidspaces)
/data/local/Droidspaces/bin/droidspaces --name=Ubuntu run make -C /root/droidspaces-build droidspaces CC=gcc CFLAGS="-static -O2 -I/root/droidspaces-build/src/include" LDFLAGS="-static"

# Move output
cp /mnt/Droidspaces/Ubuntu/root/droidspaces-build/output/droidspaces /data/local/Droidspaces/bin/droidspaces.tmp
chmod 755 /data/local/Droidspaces/bin/droidspaces.tmp
mv -f /data/local/Droidspaces/bin/droidspaces.tmp /data/local/Droidspaces/bin/droidspaces
echo "SUCCESS"
