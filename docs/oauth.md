# Accesso con Google e Microsoft (OAuth2)

Kaamos Mail usa IMAP e SMTP anche per Gmail e Outlook, come Thunderbird e
Apple Mail. Al posto della password manda un *access token* con il
meccanismo XOAUTH2. Niente Gmail API, niente Microsoft Graph.

## Come funziona

1. "Accedi con Google" apre la pagina del provider nel browser di sistema
   (su iOS in un foglio di sistema, `ASWebAuthenticationSession`). L'app
   non vede mai la tua password né il secondo fattore.
2. Il provider rimanda indietro un codice (RFC 8252):
   - su desktop l'app ascolta su `127.0.0.1` (o `localhost`) con una porta
     a caso, e il browser torna lì;
   - su iOS la pagina va a uno schema URL dell'app e il foglio si chiude da
     solo.
3. L'app scambia il codice con i token usando PKCE (RFC 7636): solo chi ha
   iniziato l'accesso conosce il `code_verifier`, quindi un codice rubato
   non serve a niente.
4. Nel portachiavi finisce solo il **refresh token**. L'access token dura
   circa un'ora e sta solo in memoria; quando scade l'app ne chiede uno
   nuovo. Se Microsoft manda un refresh token nuovo, sostituisce il vecchio.

Per ora funziona su Windows, macOS, Linux e iOS. Android arriva dopo:
i client Android di Google accettano uno schema URL solo con impostazioni
in più, e va provato su un dispositivo.

## Registrare l'app

I client ID non sono segreti, ma ogni build deve averne uno. Si passano
con `--dart-define`:

```sh
# Desktop
flutter run -d windows \
  --dart-define=KAAMOS_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=KAAMOS_GOOGLE_CLIENT_SECRET=GOCSPX-xxxx \
  --dart-define=KAAMOS_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000

# iOS: Google vuole un client a parte, Microsoft usa lo stesso
flutter run -d ios \
  --dart-define=KAAMOS_GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com \
  --dart-define=KAAMOS_MICROSOFT_CLIENT_ID=00000000-0000-0000-0000-000000000000
```

Senza, i bottoni restano spenti e la schermata dice quale manca.

### Google

1. Su [Google Cloud Console](https://console.cloud.google.com/) crea un
   progetto.
2. In "Google Auth Platform" configura la schermata di consenso: tipo
   **External**, nome dell'app, email di supporto.
3. In "Data access" aggiungi lo scope `https://mail.google.com/`. È uno
   scope *restricted*.
4. In "Audience" lascia l'app in **Testing** e aggiungi gli utenti di
   test (massimo 100).
5. In "Clients" crea un client di tipo **Desktop app**. Ottieni client ID
   e client secret. Per i client desktop Google dice che il secret non è
   confidenziale, ma il suo token endpoint lo vuole comunque.
6. Per iOS crea un secondo client di tipo **iOS** con bundle ID
   `dev.kaamos.kaamosMail`. Non ha secret. Il redirect è il client ID
   rovesciato (`com.googleusercontent.apps.yyyy:/oauth2redirect`) e l'app
   lo calcola da sola.

Da sapere:

- Finché l'app è in Testing, Google fa scadere i refresh token dopo 7
  giorni. Poi bisogna rimuovere e aggiungere di nuovo l'account.
- Per uscire da Testing con uno scope restricted serve la verifica di
  Google, con una valutazione di sicurezza annuale a pagamento.

### Microsoft

1. Su [Microsoft Entra](https://entra.microsoft.com/) vai in "App
   registrations" e scegli "New registration".
2. In "Supported account types" scegli gli account di qualsiasi
   organizzazione e gli **account Microsoft personali**.
3. Come redirect URI scegli la piattaforma **Public client/native (mobile
   & desktop)** con valore `http://localhost`. Microsoft ignora la porta
   per gli indirizzi loopback.
   Per iOS aggiungi la piattaforma **iOS / macOS** con bundle ID
   `dev.kaamos.kaamosMail`. Entra crea il redirect
   `msauth.dev.kaamos.kaamosMail://auth`, che è quello che usa l'app.
4. In "API permissions" aggiungi i permessi delegati:
   - `IMAP.AccessAsUser.All` e `SMTP.Send` di Office 365 Exchange Online
     (`https://outlook.office.com`);
   - `offline_access`, `openid`, `email` e `profile`.
5. Il client ID è l'"Application (client) ID". Non serve nessun secret.

Da sapere: sugli account di lavoro l'amministratore può aver spento IMAP o
SMTP AUTH. In quel caso l'accesso riesce ma la verifica dei server fallisce.
