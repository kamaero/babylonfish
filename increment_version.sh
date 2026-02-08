#!/bin/bash

VERSION_FILE="Sources/BabylonFish3/Version.swift"

# 1. Read current version from Version.swift
# grep for string inside quotes
CURRENT_VERSION=$(grep -o '"[^"]*"' "$VERSION_FILE" | tr -d '"')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not read version from $VERSION_FILE"
    exit 1
fi

echo "Current version: $CURRENT_VERSION"

# 2. Increment Patch Version
IFS='.' read -r -a parts <<< "$CURRENT_VERSION"
MAJOR=${parts[0]}
MINOR=${parts[1]}
PATCH=${parts[2]}

# Handle case where version might not have 3 parts (e.g. 1.0)
if [ -z "$PATCH" ]; then
    PATCH=0
fi

PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo "New version: $NEW_VERSION"

# 3. Update Version.swift
sed -i '' "s/static let current = \"$CURRENT_VERSION\"/static let current = \"$NEW_VERSION\"/" "$VERSION_FILE"

echo "Version updated to $NEW_VERSION"
