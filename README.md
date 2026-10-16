# SENTINEL ONE

App Android Flutter per associare un secondo telefono come telecamera e visualizzare il flusso via WebRTC.

## Associazione QR implementata

1. Sul telefono da usare come telecamera apri **Dispositivi → Mostra QR per associare un telefono**.
2. Sul telefono monitor apri **Dispositivi → Scansiona QR di una telecamera** e inquadra il QR.
3. Il monitor consuma un ticket monouso, valido 3 minuti. Il server rilascia credenziali separate per telecamera e monitor; il token amministrativo non viene inserito nel QR.
4. Sul telefono telecamera premi **Avvia questa telecamera**. La sessione WebRTC parte automaticamente su entrambi i dispositivi.

Il servizio di segnalazione usa HTTPS/WSS su Render. Il QR non contiene le credenziali di sessione a lungo termine. Le associazioni scadono dopo 24 ore e possono essere rigenerate mostrando un nuovo QR. I ticket sono monouso e il servizio applica un limite basilare alle richieste per IP.

## Limiti importanti da non confondere con un prodotto finito

- L’associazione QR e il flusso WebRTC sono collegati nel codice, ma non posso dichiarare verificato il video end-to-end finché non viene eseguito un test su due telefoni fisici.
- Il servizio Render gratuito può andare in sleep; non è adatto a un sistema di sicurezza affidabile 24/7.
- La configurazione attuale usa STUN pubblico. Alcune reti mobili, router e NAT richiedono un server TURN; senza TURN la connessione può non riuscire. Il fallback TURN non è ancora provisionato automaticamente.
- La schermata dashboard non mostra più telecamere o eventi inventati. Il conteggio resta a zero finché non esiste un collegamento reale; l’elenco dei dispositivi non è ancora persistito tra riavvii.
- Mancano ancora gestione utenti/casa, revoca persistente, notifiche push, registrazione eventi e integrazioni Tapo/RTSP/ONVIF. Non usare questa build come unico sistema di sicurezza.

## Servizio di segnalazione

Il server usa `server/signaling_server.py` e una singola porta HTTP per:
- `GET /health` stato servizio
- `POST /pair/create` creazione ticket QR e credenziale telecamera
- `POST /pair/consume` consumo monouso del ticket e credenziale monitor
- `GET /signal/{room}` WebSocket autenticato per SDP/ICE WebRTC

Il relay trasporta solo messaggi di segnalazione, non il video. Il video viaggia attraverso WebRTC tra i telefoni. Le credenziali per stanza vengono conservate in memoria: un riavvio del servizio invalida le associazioni in corso. Per uso reale servono storage condiviso, protezioni anti-abuso più robuste, monitoraggio, TURN e test di sicurezza.

Il servizio pubblicato atteso dall’app è `https://sentinel-one-signaling.onrender.com` / `wss://sentinel-one-signaling.onrender.com`. La variabile `PUBLIC_SERVER` può sovrascrivere l’indirizzo WSS restituito dall’API.

## Test e build

```sh
python -m pip install -r server/requirements.txt
python -m unittest discover -s server -p 'test_*.py'
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

La workflow GitHub Actions esegue i test server, l’analisi Flutter e produce un APK come artifact quando la build termina con successo.
