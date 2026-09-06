import AppKit

// Disegna l'icona di Avvisa: una campanella bianca su fondo caldo, nella forma
// arrotondata delle icone di macOS. Nessuna immagine esterna: tutto disegnato qui.

func disegna(lato: CGFloat) -> NSImage {
    // La tela va creata a pixel esatti: lasciando fare a NSImage, su uno schermo
    // Retina esce al doppio, e allora iconutil scarta le misure piccole — quelle
    // che servono proprio alle notifiche.
    guard let tela = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(lato), pixelsHigh: Int(lato),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return NSImage(size: NSSize(width: lato, height: lato)) }
    tela.size = NSSize(width: lato, height: lato)

    let immagine = NSImage(size: NSSize(width: lato, height: lato))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: tela)
    guard let contesto = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState(); return immagine
    }
    contesto.setShouldAntialias(true)
    contesto.interpolationQuality = .high

    // Margine come nelle icone di sistema: il disegno non tocca i bordi.
    let margine = lato * 0.086
    let corpo = CGRect(x: margine, y: margine,
                       width: lato - margine * 2, height: lato - margine * 2)
    let raggio = corpo.width * 0.2237

    let forma = NSBezierPath(roundedRect: corpo, xRadius: raggio, yRadius: raggio)
    contesto.saveGState()
    forma.addClip()

    let sfumatura = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.72, blue: 0.23, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.44, blue: 0.16, alpha: 1),
    ])
    sfumatura?.draw(in: corpo, angle: -90)

    // Un velo chiaro in alto: dà volume senza inventare un riflesso finto.
    let velo = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.28),
        NSColor(white: 1, alpha: 0.0),
    ])
    velo?.draw(in: CGRect(x: corpo.minX, y: corpo.midY,
                          width: corpo.width, height: corpo.height / 2), angle: -90)
    contesto.restoreGState()

    // La campanella, presa dai simboli di sistema così resta nitida a ogni misura.
    let configurazione = NSImage.SymbolConfiguration(pointSize: corpo.height * 0.52, weight: .semibold)
    if let simbolo = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "avviso")?
        .withSymbolConfiguration(configurazione) {
        let dimensione = simbolo.size

        // Il simbolo va colorato su una tela trasparente a parte: colorarlo
        // direttamente sopra il fondo tingerebbe di bianco tutto il riquadro.
        let bianca = NSImage(size: dimensione)
        bianca.lockFocus()
        simbolo.draw(in: CGRect(origin: .zero, size: dimensione))
        NSColor.white.set()
        CGRect(origin: .zero, size: dimensione).fill(using: .sourceAtop)
        bianca.unlockFocus()

        let riquadro = CGRect(
            x: corpo.midX - dimensione.width / 2,
            y: corpo.midY - dimensione.height / 2,
            width: dimensione.width, height: dimensione.height)

        contesto.saveGState()
        contesto.setShadow(offset: CGSize(width: 0, height: -corpo.height * 0.012),
                           blur: corpo.height * 0.03,
                           color: NSColor(white: 0, alpha: 0.28).cgColor)
        bianca.draw(in: riquadro)
        contesto.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    immagine.addRepresentation(tela)
    return immagine
}

let cartella = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Avvisa.iconset"
try? FileManager.default.createDirectory(atPath: cartella, withIntermediateDirectories: true)

// I nomi si compongono da qui: iconutil li vuole esattamente in questa forma.
let misure: [(Int, Int, String)] = [16, 32, 128, 256, 512].flatMap { lato in
    [1, 2].map { scala -> (Int, Int, String) in
        let suffisso = scala == 1 ? "" : "@" + String(scala) + "x"
        return (lato, scala, "icon_\(lato)x\(lato)" + suffisso + ".png")
    }
}

for (punti, scala, nome) in misure {
    let pixel = punti * scala
    let immagine = disegna(lato: CGFloat(pixel))
    guard let rappresentazione = immagine.representations.first as? NSBitmapImageRep,
          let png = rappresentazione.representation(using: .png, properties: [:])
    else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(cartella)/\(nome)"))
}
print("icone scritte in \(cartella)")
