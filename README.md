# Kaamos Mail

Un client email libero (GPLv3) per Windows, macOS, Android e iOS, parte di
**Kaamos Project**. Linux arriva in fase 2.

È **solo un client**: parla direttamente con il tuo server IMAP/SMTP. Nessun
server Kaamos in mezzo, nessuna telemetria. Le password stanno solo nel
portachiavi del sistema operativo.

## Cosa fa l'MVP

- Un account IMAP/SMTP, con verifica dei server prima di salvarlo.
- Cartelle, lista dei messaggi con "Carica altri", ricerca sul server.
- Lettura di mail in testo e in HTML (WebView chiusa a chiave, vedi sotto).
- Immagini remote bloccate finché non premi "Carica immagini".
- Allegati: apri quelli ricevuti, allega file a quelli che scrivi.
- Scrivi, Rispondi, Rispondi a tutti, Inoltra (solo testo semplice).
- Bozze salvate sul server, copia in Inviati (tranne Gmail, che la fa da sé).
- Stella, letto/non letto, Archivia, Cestino.

## Fase 2 (in corso)

- Più account: aggiungi, passa dall'uno all'altro, rimuovi.
- "Tutte le caselle": le Inbox di tutti gli account in una lista sola,
  ordinate per data di arrivo. Ogni azione (stella, letto, archivia,
  rispondi) la fa l'account del messaggio. Per ora niente ricerca né
  "Carica altri" in questa vista: mostra gli ultimi 50 messaggi.
- Accesso con Google e Microsoft (OAuth2 + XOAUTH2) su desktop. Come
  registrare l'app e avviarla con i client ID: [docs/oauth.md](docs/oauth.md).

## Architettura

```
lib/
  main.dart                 crea i servizi veri e avvia l'app
  src/
    core/                   logica pura, senza Flutter: modelli, testo, pulizia HTML
    data/                   IMAP/SMTP (enough_mail), cache SQLite, portachiavi
    state/                  MailboxController (ChangeNotifier), bozze
    ui/                     schermate e widget (kaamos_project_ui)
```

- **Stato**: un `ChangeNotifier` per la casella, letto con
  `ListenableBuilder`. Niente librerie di stato: per un account e una
  casella bastano.
- **Servizi**: arrivano ai widget con un `InheritedWidget`
  (`MailEnvironment`). Nei test si sostituiscono con server finto e cache
  in memoria.
- **Cache (opzione A)**: all'avvio si mostra subito la cache SQLite, poi
  si chiede al server `UIDVALIDITY` e la lista degli UID. Si scaricano solo
  i messaggi nuovi, si aggiornano i flag di quelli noti, si tolgono quelli
  spariti. Se `UIDVALIDITY` cambia, la cache della cartella si svuota.
- **Azioni ottimistiche**: stella e letto cambiano subito sullo schermo; se
  il server rifiuta, tornano come prima e compare l'errore.

## Sicurezza delle mail HTML

Tre muri, uno dentro l'altro:

1. **Pulizia a lista bianca** (`HtmlSanitizer`): restano solo tag e
   attributi noti; script, iframe, form, svg spariscono con il contenuto;
   via `on*`, `javascript:`, `expression()`, `@import`.
2. **JavaScript spento** nella WebView.
3. **Niente rete**: la pagina ha una Content-Security-Policy
   `default-src 'none'`; le immagini remote passano solo dopo "Carica
   immagini". Ogni navigazione viene annullata e il link si apre nel
   browser di sistema.

Il Ccn non finisce mai nelle intestazioni: va solo nella lista dei
destinatari SMTP.

## Librerie

| Cosa | Pacchetto | Perché |
|---|---|---|
| IMAP/SMTP | `enough_mail` | la libreria Dart più usata e testata, MPL-2.0 |
| Cache | `sqlite3` | SQLite diretto, senza ORM: poche tabelle, query semplici |
| Portachiavi | `flutter_secure_storage` | Keychain su Apple, DPAPI su Windows, Keystore su Android |
| Mail HTML | `flutter_inappwebview` | WebView con controllo su JS e navigazione |
| File | `file_picker`, `open_filex`, `path_provider`, `url_launcher` | |
| UI | `kaamos_project_ui` | il design system Kaamos (dipendenza git) |

## Avviarla

Serve Flutter 3.50.1.

```sh
flutter pub get
flutter run -d windows   # oppure macos, ios, android
```

Controlli che fa anche la CI:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Note per piattaforma

- **Windows**: la WebView usa WebView2 (già presente su Windows 10/11
  aggiornati). Le password stanno in `flutter_secure_storage.dat` nella
  cartella dati dell'app, cifrate con DPAPI: la chiave è legata al tuo
  utente Windows. Per compilare con Visual Studio 2026 servono il
  componente ATL e la macro in `windows/CMakeLists.txt` (vedi il commento lì).
- **macOS**: l'app è in sandbox con il permesso `network.client`. Se il
  portachiavi rifiuta di salvare, va aggiunta la capability "Keychain
  Sharing" in Xcode (serve un team di firma).
- **iOS**: le password vanno nel Keychain; niente permessi speciali.
- **Android**: permesso `INTERNET`; backup disattivato, così cache e chiavi
  non finiscono nel backup di Google.
- **Linux (fase 2)**: serve GNOME Keyring o KWallet (Secret Service).
  Senza, l'app non parte e lo spiega. Le mail HTML per ora si vedono come
  testo, perché `flutter_inappwebview` non supporta Linux.

## Licenza

GPL-3.0. Vedi [LICENSE](LICENSE).
