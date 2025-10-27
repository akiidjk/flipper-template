#!/bin/bash

# Flipper Zero Zig Template Setup Script

set -e

echo "========================================="
echo "  Flipper Zero Zig Template Setup"
echo "========================================="
echo ""

# Only ask what actually matters
read -p "App ID (lowercase_with_underscores): " APP_ID
if [ -z "$APP_ID" ]; then
    echo "Error: App ID is required"
    exit 1
fi

read -p "App Name (displayed in menu): " APP_NAME
if [ -z "$APP_NAME" ]; then
    echo "Error: App Name is required"
    exit 1
fi

read -p "Description: " APP_DESC
APP_DESC=${APP_DESC:-A Zig application for Flipper Zero}

read -p "Author Name: " AUTHOR_NAME
AUTHOR_NAME=${AUTHOR_NAME:-Anonymous}

read -p "GitHub URL (optional): " WEB_URL
WEB_URL=${WEB_URL:-https://github.com/yourusername/flipper-app}

# Create the application.fam file
cat > application.fam << EOF
App(
    appid="$APP_ID",
    apptype=FlipperAppType.EXTERNAL,
    name="$APP_NAME",
    entry_point="start",
    stack_size=2 * 1024,
    fap_version="0.1",
    fap_icon="icon.png",
    fap_category="Tools",
    fap_description="$APP_DESC",
    fap_author="$AUTHOR_NAME",
    fap_weburl="$WEB_URL",
    sources=["zig-out/bin/app.o"],
    requires=["gui"],
    fap_extbuild=[
        ExtFile(path="zig-out/bin/app.o", command=""),
    ],
)
EOF

echo ""
echo "✓ application.fam created!"
echo ""
echo "Next steps:"
echo "  1. Edit src/root.zig to write your app"
echo "  2. Run 'zig build fap' to build everything"
echo ""
