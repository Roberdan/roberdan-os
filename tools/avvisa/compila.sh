#!/bin/zsh
# Compila Avvisa.app, ne disegna l'icona e la registra su questo Mac.
emulate -L zsh
set -eu
cd "${0:A:h}"
app="$HOME/Applications/Avvisa.app"
temporaneo=$(mktemp -d "${TMPDIR:-/tmp}/avvisa-compila.XXXXXX")
trap 'rm -rf "$temporaneo"' EXIT

xcrun swiftc -parse-as-library -O -warnings-as-errors -target arm64-apple-macosx13.0 \
  -o "$temporaneo/Avvisa" Avvisa.swift

# L'icona si disegna a pixel esatti: lasciando fare a NSImage, su uno schermo
# Retina esce al doppio e iconutil scarta le misure piccole — quelle che
# servono proprio ai banner delle notifiche.
xcrun swiftc -O -o "$temporaneo/generaicona" icona.swift
"$temporaneo/generaicona" "$temporaneo/Avvisa.iconset" >/dev/null

# Il Centro Notifiche legge l'icona dal catalogo compilato, non dal solo file
# .icns: si produce anche quello, come fa Xcode.
mkdir -p "$temporaneo/Avvisa.xcassets/AppIcon.appiconset"
cp "$temporaneo/Avvisa.iconset"/*.png "$temporaneo/Avvisa.xcassets/AppIcon.appiconset/"
print '{"info":{"author":"xcode","version":1}}' > "$temporaneo/Avvisa.xcassets/Contents.json"
{
  print '{ "info": {"author":"xcode","version":1}, "images": ['
  primo=1
  for misura in 16 32 128 256 512; do
    for scala in 1 2; do
      (( primo )) || print -n ','
      primo=0
      if (( scala == 1 )); then nome="icon_${misura}x${misura}.png"
      else nome="icon_${misura}x${misura}@2x.png"; fi
      print -n "{\"filename\":\"$nome\",\"idiom\":\"mac\",\"scale\":\"${scala}x\",\"size\":\"${misura}x${misura}\"}"
    done
  done
  print ']}'
} > "$temporaneo/Avvisa.xcassets/AppIcon.appiconset/Contents.json"

mkdir -p "$temporaneo/uscita"
xcrun actool "$temporaneo/Avvisa.xcassets" --compile "$temporaneo/uscita" \
  --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist "$temporaneo/parziale.plist" \
  --output-format human-readable-text >/dev/null

# actool produce un .icns con poche misure: per il Finder e il Dock si usa
# quello completo, costruito da iconutil.
iconutil -c icns "$temporaneo/Avvisa.iconset" -o "$temporaneo/uscita/AppIcon.icns"

install -d "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 644 Info.plist "$app/Contents/Info.plist"
install -m 755 "$temporaneo/Avvisa" "$app/Contents/MacOS/Avvisa"
install -m 644 "$temporaneo/uscita/Assets.car" "$app/Contents/Resources/Assets.car"
install -m 644 "$temporaneo/uscita/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier it.roberdan.notificatore "$app"
codesign --verify --strict "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
print 'Avvisa compilata, con icona, e registrata su questo Mac.'
