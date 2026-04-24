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

if [ $? -ne 0 ]; then
    echo "Error: Upload failed"
    exit 1
fi

echo "Regenerating index.html..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "cd ${REMOTE_DIR} && ls -t *.apk | awk 'BEGIN {
    print \"<!DOCTYPE html><html><head><meta charset=\\\"utf-8\\\"><title>Leggio APK</title>\"
    print \"<style>body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:0 20px}\"
    print \"a{display:block;padding:8px 0;color:#1a73e8;text-decoration:none}\"
    print \"a:hover{text-decoration:underline}</style></head><body>\"
    print \"<h1>Leggio</h1>\"
}
{ print \"<a href=\\\"\" \$0 \"\\\">\" \$0 \"</a>\" }
END { print \"</body></html>\" }' > index.html"

echo "Deployed: https://android.kreilos.fr/${APK_NAME}"
