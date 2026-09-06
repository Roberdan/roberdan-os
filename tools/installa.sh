#!/bin/zsh
# Installa gli strumenti locali di questa cartella su questo Mac.
# Non copia nulla di duplicato: i comandi diventano collegamenti al repository,
# così modificare il repository cambia subito il comportamento.
emulate -L zsh
set -eu
qui="${0:A:h}"

if [[ $(uname) != Darwin ]]; then
  print -u2 'Questi strumenti servono solo su macOS.'
  exit 1
fi

mkdir -p "$HOME/.local/bin"

# 1. Il comando che comprime i PDF.
if ! command -v gs >/dev/null 2>&1; then
  print -u2 'Manca Ghostscript: installalo con  brew install ghostscript'
  exit 1
fi
ln -sf "$qui/comprimi-pdf/comprimi-pdf" "$HOME/.local/bin/comprimi-pdf"
print 'comprimi-pdf collegato in ~/.local/bin'

# 2. Il notificatore, che avvisa quando la compressione è finita.
ln -sf "$qui/avvisa/avvisa" "$HOME/.local/bin/avvisa"
if command -v xcrun >/dev/null 2>&1; then
  "$qui/avvisa/compila.sh"
else
  print -u2 'Senza gli strumenti di Xcode non posso compilare Avvisa.app: le notifiche non ci saranno.'
fi

# 3. L'azione rapida del Finder (tasto destro su un PDF).
servizi="$HOME/Library/Services"
mkdir -p "$servizi"
rm -rf "$servizi/Comprimi PDF.workflow"
cp -R "$qui/comprimi-pdf/Comprimi PDF.workflow" "$servizi/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$servizi/Comprimi PDF.workflow" 2>/dev/null || true   # i workflow non si registrano qui: ci pensa pbs

# Senza questa riga il comando finisce sotto «Servizi» invece che fra le
# «Azioni rapide» del menu del Finder.
chiave='NSServicesStatus:"(null) - Comprimi PDF - runWorkflowAsService"'
plist="$HOME/Library/Preferences/pbs.plist"
for modo in ContextMenu FinderPreview ServicesMenu TouchBar; do
  /usr/libexec/PlistBuddy -c "Set :$chiave:presentation_modes:$modo true" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$chiave:presentation_modes:$modo bool true" "$plist" 2>/dev/null \
    || true
done
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
print 'Azione rapida «Comprimi PDF» installata nel menu del Finder.'

# 4. La scorciatoia da terminale.
if ! grep -q "alias comprimipdf=" "$HOME/.zshrc" 2>/dev/null; then
  print '\n# Comprime un PDF accanto all'\''originale (roberdan-os/tools).' >> "$HOME/.zshrc"
  print "alias comprimipdf='\$HOME/.local/bin/comprimi-pdf'" >> "$HOME/.zshrc"
  print 'Aggiunto l'\''alias comprimipdf in ~/.zshrc'
fi

print '\nFatto. Apri un terminale nuovo, oppure usa il tasto destro su un PDF nel Finder.'
