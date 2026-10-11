# Kingsburg — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Kingsburg** (seconda edizione, gioco base) di Andrea Chiarvesio
e Luca Iennaco (Giochi Uniti / Stratelibri). Componenti, illustrazioni e regole © dei rispettivi autori:
le immagini vengono dal modulo Tabletop Simulator e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Kingsburg/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Da 2 a 5 governatori** (Rosso, Giallo, Blu, Nero, Verde), ognuno Umano o IA. Con più umani sullo
  stesso dispositivo si gioca a turno (in Kingsburg non ci sono informazioni nascoste, a parte la carta
  Invasori vista con Generale e Regina, che compare solo a chi l'ha guardata).
- **Regole complete del gioco base**, 2ª edizione: 5 anni × 8 fasi, Aiuto del Re (dado bianco o merce),
  Premio del Re, Agente del Re (Consigliere già occupato oppure secondo edificio), i 18 Consiglieri con
  tutte le scelte, i 20 edifici con i loro effetti (Statua, Cappella, Mercato, Fattorie, Gilda dei Mercanti,
  Locanda, Caserma, Scuderia, Mura, Fortezza, Argano, Municipio, Ambasciata, Cattedrale, bonus contro
  Goblin/Zombi/Demoni…), gettoni +2, Mercenari, battaglia d'inverno con le 25 carte Invasori,
  distruzione degli edifici, regola dei dadi neutrali per 2 giocatori, spareggi finali.
- **IA** su tre livelli (Facile / Normale / Difficile; i pesi del Difficile sono stati regolati con centinaia di partite IA contro IA). Valuta ogni cosa in punti vittoria attesi: le merci
  pesano di più se servono agli edifici che ha in programma, i soldati quanto migliorano la battaglia
  attesa (con le carte possibili dell'anno, o quella vista), e per i Consiglieri cerca la migliore
  ripartizione di tutti i suoi dadi, giocando prima quelli che gli avversari potrebbero rubargli.
- **Regole in breve** dal menu e in partita (pulsante REGOLE), diario completo (DIARIO) e cronaca
  sul tabellone.

## Comandi
- Clic sui dadi per sceglierli, poi clic su un Consigliere evidenziato in verde. Senza dadi scelti i
  riquadri gialli mostrano i Consiglieri raggiungibili: se c'è un solo modo di arrivarci basta il clic.
- Pulsanti **+2** (gettone) e **Mercato ±1** quando disponibili; PASSA per smettere di influenzare.
- In costruzione, clic su una carta evidenziata della provincia (oppure NON COSTRUIRE).
- Clic su un giocatore per vederne la provincia; passa il mouse su edifici e Consiglieri per i dettagli.

## Gioco online
Dal menu, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database, piano gratuito), con le stanze sotto `kingsburg/rooms`.

- **Chi crea la stanza** sceglie prima nel menu i colori e il livello dell'IA: i colori su UMANO
  diventano i posti per gli amici (il primo è il suo). Scrive il nome, preme *Crea una stanza* e comunica
  il codice di 4 lettere. Quando ci sono tutti preme *Inizia online*: i posti liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- Ogni decisione (Consigliere, merce, edificio, soldati…) è una mossa numerata nel database
  (`acts/0`, `acts/1`, …). Tutti i dispositivi fanno girare lo stesso motore con lo stesso seme e
  applicano le stesse mosse, quindi la partita è identica ovunque. I colori IA li gioca il dispositivo
  di chi ha creato la stanza.
- **Se cade la linea** si rientra con lo stesso codice e *Entra*. Se un giocatore tace per un minuto,
  al suo posto gioca l'IA finché non rientra.

**Configurazione Firebase.** Le regole sono in `firebase/database.rules.json` e comprendono anche quelle
degli altri giochi (Ultimo chilometro, Snow Tails, STATUS, World Order) più la nuova sezione `kingsburg`:
vanno pubblicate nella console di Firebase (Realtime Database → Regole) al posto delle precedenti.
Senza questo passaggio la creazione della stanza risponde "Permission denied".

**Prove senza Firebase.** `tests/firebase_mock.py` è un finto Firebase locale. Con `KB_DB_URL`,
`KB_AUTH_URL` e `KB_REFRESH_URL` che puntano lì, `tests/online_play.gd` fa giocare una partita intera a
due istanze (`KB_ROLE=host` e `guest`, più un colore IA; con `KB_PHASE=drop` e poi `back` l'ospite esce
a metà e rientra). Alla fine ognuna stampa l'impronta della partita, che deve coincidere.

## Struttura
```
scripts/data/kb_data.gd      Consiglieri, edifici, carte Invasori, coordinate del tabellone
scripts/core/engine.gd       motore delle regole (nessuna dipendenza dalla UI)
scripts/core/ai.gd           IA
scripts/net/                 Firebase (REST) e partita online in lockstep
scripts/ui/                  menu, vista di gioco, regole
tests/sim.gd                 godot --headless -s res://tests/sim.gd -- 20 4    (partite IA contro IA)
tests/shot.gd                xvfb-run godot -s res://tests/shot.gd -- game     (screenshot)
assets/                      tabellone, edifici, carte, dadi, stemmi, icone (dal modulo TTS), font OFL
```

## Scelte da verificare
- Un solo gettone +2 per giocatore in ogni stagione (dai "Chiarimenti" del regolamento).
- Statua e Cappella valgono anche per i dadi bianchi (come nell'esempio del regolamento) e si possono
  usare una volta ciascuna per stagione, in qualsiasi ordine.
- Premio del Re: serve almeno un edificio (a inizio partita nessuno lo riceve).
- Con 2 giocatori i dadi neutrali contano come Consiglieri già influenzati: l'Agente del Re può usarli.
- L'Agente del Re per il secondo edificio si usa nel proprio turno di costruzione.
- Espansioni (*To Forge a Realm*: linee di edifici alternative, carte Fato e Governatore, Capricci,
  Rinforzi determinabili) non ancora incluse.
