#!/bin/bash
set -e

# ─── Configuration ───────────────────────────────────────────────────────────
REPO="Digitally-Simple/BingoBite"
APPCAST="docs/appcast.xml"
SPARKLE_SIGN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null)

# ─── Input ───────────────────────────────────────────────────────────────────
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: ./release.sh <path-to-exported-BingoBite.app> <version>"
  echo "Example: ./release.sh ~/Desktop/BingoBite.app 1.0.1"
  exit 1
fi

APP_PATH="$1"
VERSION="$2"
ZIP_NAME="BingoBite-${VERSION}.zip"
BUILD_DIR="build/release"
RELEASE_NOTES="RELEASE_NOTES.md"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ App not found at: $APP_PATH"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/$RELEASE_NOTES" ]; then
  echo "❌ $RELEASE_NOTES not found. Create it with your release notes before running."
  exit 1
fi

NOTES=$(cat "$SCRIPT_DIR/$RELEASE_NOTES")
if [ -z "$NOTES" ]; then
  echo "❌ Release notes are empty. Aborting."
  exit 1
fi

if [ -z "$SPARKLE_SIGN" ]; then
  echo "❌ Could not find Sparkle sign_update tool in DerivedData"
  exit 1
fi

mkdir -p "$BUILD_DIR"

# ─── Step 1: Notarize ───────────────────────────────────────────────────────
echo "📦 Zipping app for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$ZIP_NAME"

echo "🍎 Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/$ZIP_NAME" --keychain-profile "notarytool" --wait

echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# ─── Step 2: Re-zip after stapling and sign with Sparkle ────────────────────
echo "📦 Re-zipping stapled app..."
rm "$BUILD_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$ZIP_NAME"

echo "🔑 Signing with Sparkle EdDSA key..."
SIGN_OUTPUT=$("$SPARKLE_SIGN" "$BUILD_DIR/$ZIP_NAME")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

echo "   Signature: $ED_SIGNATURE"
echo "   Length: $LENGTH"

# ─── Step 3: Upload to GitHub Releases ──────────────────────────────────────
echo "🚀 Creating GitHub release v${VERSION}..."
gh release create "v${VERSION}" "$BUILD_DIR/$ZIP_NAME" \
  --title "v${VERSION}" \
  --notes "$NOTES"

# ─── Step 4: Update appcast.xml ─────────────────────────────────────────────
echo "📝 Updating appcast.xml..."
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
BUILD_NUMBER=$(echo "$VERSION" | awk -F. '{print $1*10000 + $2*100 + $3}')

# Convert markdown list items to HTML
HTML_NOTES=$(echo "$NOTES" | sed 's/^- /          <li>/;s/$/<\/li>/')

# Build the new item XML in a temp file
ITEM_FILE=$(mktemp)
cat > "$ITEM_FILE" <<EOF

    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
${HTML_NOTES}
        </ul>
      ]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}"
      />
    </item>
EOF

# Insert new item after <language> line
sed -i '' "/<language>en<\/language>/r $ITEM_FILE" "$APPCAST"
rm "$ITEM_FILE"

# ─── Step 5: Commit and push ────────────────────────────────────────────────
echo "📤 Pushing appcast update..."
# Reset release notes template for next time
echo "- Bug fixes and improvements" > "$SCRIPT_DIR/$RELEASE_NOTES"
git add "$APPCAST" "$SCRIPT_DIR/$RELEASE_NOTES"
git commit -m "Release v${VERSION}"
git push

echo ""
echo "✅ Released BingoBite v${VERSION}"
echo "   GitHub: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "   Appcast: https://digitally-simple.github.io/BingoBite/appcast.xml"
