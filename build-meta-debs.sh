#!/bin/bash
# Build meta packages (stable, master, unstable) for ubuntu-24.04-x86_64.
# These configure apt sources on target machines to point at the correct repo channel.
# Usage: ./build-meta-debs.sh <gpg_key_file> <output_dir>
set -e

GPG_KEY_FILE="${1:-signing-key.asc}"
OUTPUT_DIR="${2:-/build/meta}"
PLATFORM="ubuntu-24.04-x86_64"

GPG_KEY=""
if [ -f "$GPG_KEY_FILE" ]; then
  GPG_KEY=$(cat "$GPG_KEY_FILE")
else
  echo "WARNING: $GPG_KEY_FILE not found, meta debs will have empty GPG key"
fi

mkdir -p "$OUTPUT_DIR"

for CHANNEL in stable master unstable; do
  PKG="rackspace-cloud-monitoring-meta-${CHANNEL}"
  DIR="${OUTPUT_DIR}/${PKG}"
  CHANNEL_UPPER="$(echo "$CHANNEL" | sed 's/./\U&/')"

  rm -rf "$DIR"
  mkdir -p "${DIR}/DEBIAN" "${DIR}/usr/share/doc/${PKG}"

  # control
  cat > "${DIR}/DEBIAN/control" <<EOF
Package: ${PKG}
Version: 1.0
Architecture: all
Maintainer: Rackspace Cloud Monitoring <monitoring@rackspace.com>
Installed-Size: 14
Section: unknown
Priority: extra
Description: Rackspace Cloud Monitoring ${CHANNEL_UPPER} Repo
EOF

  # postinst — Ubuntu 24.04 uses signed-by keyrings instead of apt-key
  KEYRING_PATH="/etc/apt/keyrings/rackspace-monitoring.gpg"

  cat > "${DIR}/DEBIAN/postinst" <<POSTINST_HEADER
#!/bin/sh
#
KEYRING="${KEYRING_PATH}"
REPOCONFIG="deb [signed-by=${KEYRING_PATH}] https://${CHANNEL}.packages.cloudmonitoring.rackspace.com/${PLATFORM} cloudmonitoring main"
POSTINST_HEADER

  cat >> "${DIR}/DEBIAN/postinst" <<'POSTINST_BODY'

SOURCES_PREAMBLE="### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.\n"

install_key() {
  mkdir -p /etc/apt/keyrings
  cat > /tmp/rackspace-monitoring-key.asc <<KEYDATA
POSTINST_BODY

  # Inject the actual GPG key
  echo "$GPG_KEY" >> "${DIR}/DEBIAN/postinst"

  cat >> "${DIR}/DEBIAN/postinst" <<'POSTINST_TAIL'
KEYDATA
  gpg --dearmor -o "$KEYRING" /tmp/rackspace-monitoring-key.asc 2>/dev/null
  rm -f /tmp/rackspace-monitoring-key.asc
  chmod 644 "$KEYRING"
}

create_sources_lists() {
  if [ ! "$REPOCONFIG" ]; then
    return 0
  fi

  SOURCESDIR="/etc/apt/sources.list.d"
  SOURCELIST="${SOURCESDIR}/rackspace-monitoring.list"

  if [ -d "$SOURCESDIR" ]; then
    printf "$SOURCES_PREAMBLE" > "$SOURCELIST"
    printf "$REPOCONFIG\n" >> "$SOURCELIST"
  fi
}

## MAIN ##
install_key
create_sources_lists
POSTINST_TAIL

  chmod 755 "${DIR}/DEBIAN/postinst"
  echo "${PKG} for Ubuntu 24.04" > "${DIR}/usr/share/doc/${PKG}/README.Debian"

  if [ -f /build/LICENSE.txt ]; then
    cp /build/LICENSE.txt "${DIR}/usr/share/doc/${PKG}/copyright"
  else
    echo "Copyright Rackspace" > "${DIR}/usr/share/doc/${PKG}/copyright"
  fi

  (cd "${DIR}" && find usr -type f -exec md5sum {} \;) > "${DIR}/DEBIAN/md5sums"

  dpkg-deb --build "${DIR}" "${OUTPUT_DIR}/${PKG}_1.0_all.deb"
  echo "Built: ${PKG}_1.0_all.deb"
done

echo "==> Meta packages built in ${OUTPUT_DIR}"
