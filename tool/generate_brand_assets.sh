#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_svg="$root/brand/evaluetron-worker-icon.svg"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "rsvg-convert is required." >&2
  exit 1
}

render() {
  size=$1
  output=$2
  rsvg-convert --width "$size" --height "$size" --output "$output" "$source_svg"
}

render 48 "$root/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
render 72 "$root/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
render 96 "$root/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
render 144 "$root/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
render 192 "$root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

icons="$root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
render 20 "$icons/Icon-App-20x20@1x.png"
render 40 "$icons/Icon-App-20x20@2x.png"
render 60 "$icons/Icon-App-20x20@3x.png"
render 29 "$icons/Icon-App-29x29@1x.png"
render 58 "$icons/Icon-App-29x29@2x.png"
render 87 "$icons/Icon-App-29x29@3x.png"
render 40 "$icons/Icon-App-40x40@1x.png"
render 80 "$icons/Icon-App-40x40@2x.png"
render 120 "$icons/Icon-App-40x40@3x.png"
render 120 "$icons/Icon-App-60x60@2x.png"
render 180 "$icons/Icon-App-60x60@3x.png"
render 76 "$icons/Icon-App-76x76@1x.png"
render 152 "$icons/Icon-App-76x76@2x.png"
render 167 "$icons/Icon-App-83.5x83.5@2x.png"
render 1024 "$icons/Icon-App-1024x1024@1x.png"

launch="$root/ios/Runner/Assets.xcassets/LaunchImage.imageset"
render 84 "$launch/LaunchImage.png"
render 168 "$launch/LaunchImage@2x.png"
render 252 "$launch/LaunchImage@3x.png"
