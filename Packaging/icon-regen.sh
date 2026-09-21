#!/bin/bash
# Regenerates AppIcon.icns from icon-source.svg.
set -euo pipefail
cd "$(dirname "$0")"

sips -s format png -z 1024 1024 icon-source.svg --out /tmp/icon-master.png >/dev/null
rm -rf AppIcon.iconset && mkdir AppIcon.iconset

specs="16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x"

echo "$specs" | while read -r size name; do
  sips -z "$size" "$size" /tmp/icon-master.png --out "AppIcon.iconset/${name}.png" >/dev/null
done

iconutil -c icns AppIcon.iconset -o AppIcon.icns
echo "Wrote AppIcon.icns"
