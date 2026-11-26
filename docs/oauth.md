# Accesso con Google e Microsoft (OAuth2)

Kaamos Mail usa IMAP e SMTP anche per Gmail e Outlook, come Thunderbird e
Apple Mail. Al posto della password manda un *access token* con il
meccanismo XOAUTH2. Niente Gmail API, niente Microsoft Graph.

## Come funziona

1. "Accedi con Google" apre il browser di sistema sulla pagina del provider.
   L'app non vede mai la tua password né il secondo fattore.
2. L'app ascolta su `127.0.0.1` (o `localhost`) con una porta a caso. Il
   browser torna lì con un codice (RFC 8252, "loopback redirect").
3. L'app scambia il codice con i token usando PKCE (RFC 7636): solo chi ha
   iniziato l'accesso conosce il `code_verifier`, quindi un codice rubato
   non serve a niente.
4. Nel portachiavi finisce solo il **refresh token**. L'access token dura
   circa un'ora e sta solo in memoria; quando scade l'app ne chiede uno
   nuovo. Se Microsoft manda un refresh token nuovo, sostituisce il vecchio.

Per ora funziona su Windows, macOS e Linux. iOS e Android hanno bisogno di
un ritorno con uno schema URL dell'app: arriva in un passo successivo.

## Registrare l'app

I client ID non sono segreti, ma ogni build deve averne uno. Si passano
con `--dart-define`:

```sh
flutter run -d windows \
  --dart-define=KAAMOS_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=KAAMOS_GOOGLE_CLIENT_SECRET=GOCSPX-xxxx \
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
4. In "API permissions" aggiungi i permessi delegati:
   - `IMAP.AccessAsUser.All` e `SMTP.Send` di Office 365 Exchange Online
     (`https://outlook.office.com`);
   - `offline_access`, `openid`, `email` e `profile`.
5. Il client ID è l'"Application (client) ID". Non serve nessun secret.

Da sapere: sugli account di lavoro l'amministratore può aver spento IMAP o
SMTP AUTH. In quel caso l'accesso riesce ma la verifica dei server fallisce.
