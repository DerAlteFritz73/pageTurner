#!/bin/sh
#
# Deploy APK to android.kreilos.fr
# Called automatically after flutter build apk

REMOTE_USER="chuck"
REMOTE_HOST="teutonia.kreilos.fr"
REMOTE_DIR="/var/www/android"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
APK_NAME="leggio-${VERSION}.apk"
APK_PATH="build/app/outputs/flutter-apk/${APK_NAME}"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    exit 1
fi

echo "Uploading ${APK_NAME} to ${REMOTE_HOST}..."
scp "$APK_PATH" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${APK_NAME}"

if [ $? -eq 0 ]; then
    echo "Deployed: https://android.kreilos.fr/${APK_NAME}"
else
    echo "Error: Upload failed"
    exit 1
fi
