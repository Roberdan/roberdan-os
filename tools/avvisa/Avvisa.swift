import AppKit
import UserNotifications
import OSLog

enum Problema: Error, LocalizedError {
    case messaggio(String)
    var errorDescription: String? {
        switch self { case .messaggio(let testo): return testo }
    }
}

enum Destinazione: Equatable {
    case file(URL), cartella(URL), indirizzo(URL)

    var url: URL {
        switch self {
        case .file(let url), .cartella(let url), .indirizzo(let url): return url
        }
    }

    var tipo: String {
        switch self {
        case .file: return "file"
        case .cartella: return "cartella"
        case .indirizzo: return "URL"
        }
    }

    init(_ testo: String) throws {
        guard !testo.isEmpty else { throw Problema.messaggio("Serve un percorso o un indirizzo dopo --apri.") }
        let url: URL
        if testo.contains("://") {
            guard let indirizzo = URL(string: testo), indirizzo.scheme != nil else {
                throw Problema.messaggio("Questo indirizzo non è completo: \(testo)")
            }
            if !indirizzo.isFileURL {
                self = .indirizzo(indirizzo)
                return
            }
            guard indirizzo.host == nil || indirizzo.host == "" || indirizzo.host == "localhost" else {
                throw Problema.messaggio("Per un file serve un percorso su questo Mac.")
            }
            url = indirizzo.standardizedFileURL
        } else {
            url = URL(fileURLWithPath: (testo as NSString).expandingTildeInPath).standardizedFileURL
        }
        var cartella: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &cartella) else {
            throw Problema.messaggio("Non trovo più questo percorso: \(url.path)")
        }
        self = cartella.boolValue ? .cartella(url) : .file(url)
    }
}

struct Opzioni {
    enum Modalita { case invia, risposta, stato, elenca, aiuto }
    var modalita: Modalita = .risposta
    var titolo = ""
    var testo = ""
    var destinazione: Destinazione?
    var suono = false

    init(_ argomenti: [String]) throws {
        if argomenti.isEmpty { return }
        if argomenti == ["--stato"] { modalita = .stato; return }
        if argomenti == ["--elenca"] { modalita = .elenca; return }
        if argomenti == ["--help"] || argomenti == ["-h"] { modalita = .aiuto; return }
        modalita = .invia
        var indice = 0
        while indice < argomenti.count {
            let opzione = argomenti[indice]
            if opzione == "--suono" {
                suono = true
            } else {
                guard ["--titolo", "--testo", "--apri"].contains(opzione) else {
                    throw Problema.messaggio("Opzione non riconosciuta: \(opzione). Usa --help per gli esempi.")
                }
                indice += 1
                guard indice < argomenti.count, !argomenti[indice].hasPrefix("--") else {
                    throw Problema.messaggio("Manca il valore dopo \(opzione).")
                }
                switch opzione {
                case "--titolo": titolo = argomenti[indice]
                case "--testo": testo = argomenti[indice]
                default: destinazione = try Destinazione(argomenti[indice])
                }
            }
            indice += 1
        }
        guard !titolo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problema.messaggio("Scrivi un titolo o un testo per la notifica.")
        }
    }
}

let registro = Logger(subsystem: "it.roberdan.avvisa", category: "notifiche")

func avverti(_ testo: String) {
    FileHandle.standardError.write(Data("Avvisa: \(testo)\n".utf8))
    registro.error("\(testo, privacy: .private)")
}

final class Delegato: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let opzioni: Opzioni
    let centro = UNUserNotificationCenter.current()
    let identificatore = UUID().uuidString
    var scadenza: DispatchWorkItem?
    var invioConcluso: Bool
    var azioniInCorso = 0

    init(_ opzioni: Opzioni) {
        self.opzioni = opzioni
        invioConcluso = opzioni.modalita != .invia
        super.init()
        // Il centro può consegnare il clic mentre l'app sta ancora avviandosi.
        centro.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch opzioni.modalita {
        case .invia:
            impostaScadenza(secondi: 60, messaggio: "Il consenso o il recapito stanno richiedendo troppo tempo. Controlla Impostazioni di Sistema > Notifiche > Avvisa.")
            centro.requestAuthorization(options: [.alert, .sound]) { concesso, errore in
                DispatchQueue.main.async {
                    if let errore { self.fallisci(errore.localizedDescription); return }
                    guard concesso else {
                        self.fallisci("Per mostrare gli avvisi, consenti le notifiche in Impostazioni di Sistema > Notifiche > Avvisa.")
                        return
                    }
                    self.pubblica()
                }
            }
        case .stato:
            impostaScadenza(secondi: 10, messaggio: "macOS non ha risposto alla richiesta dei permessi.")
            centro.getNotificationSettings { stato in
                self.stampaJSON([
                    "identità": Bundle.main.bundleIdentifier ?? "",
                    "autorizzazione": stato.authorizationStatus.rawValue,
                    "avvisi": stato.alertSetting.rawValue,
                    "centroNotifiche": stato.notificationCenterSetting.rawValue,
                    "suono": stato.soundSetting.rawValue
                ])
            }
        case .elenca:
            impostaScadenza(secondi: 10, messaggio: "macOS non ha risposto alla richiesta delle notifiche consegnate.")
            centro.getDeliveredNotifications { notifiche in
                self.stampaJSON(notifiche.map { notifica -> [String: Any] in
                    let richiesta = notifica.request
                    return [
                        "identità": Bundle.main.bundleIdentifier ?? "",
                        "id": richiesta.identifier,
                        "data": ISO8601DateFormatter().string(from: notifica.date),
                        "titolo": richiesta.content.title,
                        "testo": richiesta.content.body,
                        "apri": richiesta.content.userInfo["apri"] as? String ?? ""
                    ]
                })
            }
        case .risposta:
            impostaScadenza(secondi: 30, messaggio: "Non è arrivata un'azione dalla notifica.")
        case .aiuto: break
        }
    }

    private func impostaScadenza(secondi: Double, messaggio: String) {
        scadenza?.cancel()
        let lavoro = DispatchWorkItem { self.fallisci(messaggio) }
        scadenza = lavoro
        DispatchQueue.main.asyncAfter(deadline: .now() + secondi, execute: lavoro)
    }

    private func fallisci(_ testo: String) {
        avverti(testo)
        exit(1)
    }

    private func stampaJSON(_ oggetto: Any) {
        do {
            let dati = try JSONSerialization.data(withJSONObject: oggetto, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(dati)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            fallisci("Non riesco a mostrare il risultato: \(error.localizedDescription)")
        }
    }

    private func pubblica() {
        let contenuto = UNMutableNotificationContent()
        contenuto.title = opzioni.titolo
        contenuto.body = opzioni.testo
        if opzioni.suono { contenuto.sound = .default }
        if let destinazione = opzioni.destinazione {
            // Un percorso relativo non avrebbe più lo stesso significato al riavvio.
            contenuto.userInfo = ["apri": destinazione.url.absoluteString]
        }
        centro.add(UNNotificationRequest(identifier: identificatore, content: contenuto, trigger: nil)) { errore in
            DispatchQueue.main.async {
                if let errore { self.fallisci("Notifica non inviata: \(errore.localizedDescription)"); return }
                self.impostaScadenza(secondi: 10, messaggio: "macOS ha accettato l'avviso ma non ne conferma il recapito.")
                self.attendiRecapito()
            }
        }
    }

    private func attendiRecapito() {
        centro.getDeliveredNotifications { notifiche in
            DispatchQueue.main.async {
                guard !self.invioConcluso else { return }
                if notifiche.contains(where: { $0.request.identifier == self.identificatore }) {
                    self.confermaRecapito()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.attendiRecapito() }
                }
            }
        }
    }

    private func confermaRecapito() {
        guard !invioConcluso else { return }
        invioConcluso = true
        scadenza?.cancel()
        print("Notifica consegnata: \(identificatore)")
        registro.notice("Consegna confermata: \(self.identificatore, privacy: .public)")
        terminaSePronto()
    }

    private func terminaSePronto() {
        if invioConcluso && azioniInCorso == 0 { exit(0) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            self.azioniInCorso += 1
            if response.notification.request.identifier == self.identificatore {
                self.confermaRecapito()
            }
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
                completionHandler()
                self.azioniInCorso -= 1
                self.terminaSePronto()
                return
            }
            let id = response.notification.request.identifier
            registro.notice("Clic ricevuto: \(id, privacy: .public)")
            let completa: (Error?) -> Void = { errore in
                if let errore { avverti("Non riesco ad aprire la destinazione: \(errore.localizedDescription)") }
                else { registro.notice("Azione inoltrata a macOS: \(id, privacy: .public)") }
                completionHandler()
                self.azioniInCorso -= 1
                if errore != nil { exit(1) }
                self.terminaSePronto()
            }
            guard let percorso = response.notification.request.content.userInfo["apri"] as? String else {
                completa(nil)
                return
            }
            do {
                let destinazione = try Destinazione(percorso)
                registro.notice("Azione contestuale: \(destinazione.tipo, privacy: .public)")
                switch destinazione {
                case .file(let url):
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    // Lascia completare l'inoltro al Finder prima di uscire.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completa(nil) }
                case .cartella(let url), .indirizzo(let url):
                    NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, errore in
                        DispatchQueue.main.async { completa(errore) }
                    }
                }
            } catch {
                completa(error)
            }
        }
    }
}

#if !AVVISA_TEST
@main
struct Avvisa {
    static func main() {
        do {
            let opzioni = try Opzioni(Array(CommandLine.arguments.dropFirst()))
            if opzioni.modalita == .aiuto {
                print("""
                Uso: avvisa --titolo "Build finita" --testo "Puoi aprire la cartella." [--apri percorso-o-URL] [--suono]
                Un file viene selezionato nel Finder; una cartella o un URL vengono aperti al clic.
                --stato   Mostra i permessi (autorizzazione: 0 da chiedere, 1 negata, 2 consentita, 3 provvisoria).
                          Avvisi, centroNotifiche e suono: 0 non disponibili, 1 disattivati, 2 attivati.
                --elenca  Mostra le notifiche già consegnate e ancora presenti, con la loro destinazione.
                Funziona nella sessione aperta su questo Mac, anche dagli script di Automator.
                """)
                return
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegato = Delegato(opzioni)
            app.delegate = delegato
            withExtendedLifetime(delegato) { app.run() }
        } catch {
            avverti(error.localizedDescription)
            exit(2)
        }
    }
}
#endif
