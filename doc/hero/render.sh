#!/bin/sh
# Regenera doc/assets/hero-{light,dark}.png desde hero.html (Chrome headless).
set -e
cd "$(dirname "$0")"
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for t in light dark; do
  sed -e "s/__THEME__/$t/" -e "s/__LOGO__/logo.svg/" hero.html > .hero-$t.html
  "$C" --headless=new --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1280,640 --virtual-time-budget=6000 \
    --screenshot="$PWD/../assets/hero-$t.png" "file://$PWD/.hero-$t.html"
  rm .hero-$t.html
done
