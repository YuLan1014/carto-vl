#!/bin/bash

BRANCH=$(node --eval "console.log(require('./package.json').branch);")

# TODO check branch exists
echo "Ready to unpublish CARTO VL branch $BRANCH"
echo "Do you want to continue?"
read -n1 -r -p "Press Ctrl+C to cancel, or any other key to continue." key

yarn build

echo "Removing from CDN..."

node scripts/cdn/branch/unpublish.js
node scripts/cdn/invalidate.js
