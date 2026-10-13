# Kingsburg — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Kingsburg** (seconda edizione, con l'espansione *To Forge a Realm*) di Andrea Chiarvesio
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
- **Regole complete del gioco base**, 2ª edizione, e di tutti i moduli dell'espansione: 5 anni × 8 fasi, Aiuto del Re (dado bianco o merce),
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

## Espansione To Forge a Realm
Dal menu, **TO FORGE A REALM…**: i sei moduli si combinano a piacere (anche online).

1. **Linee aggiuntive**: retro del tabellone Provincia, 7 linee (A-G) con Segheria, Tagliapietre,
   Oreficeria, Zecca, Fortificazioni Sommarie, Centro Reclutamento, Campo Addestramento, Accademia Militare.
2. **Linee alternative**: ognuno ne riceve 2 a caso (oppure, con *scelta a turno*, si scelgono scoperte
   in ordine e poi in ordine inverso) e decide quali sostituire. Senza il modulo 1 si tolgono A e G.
3. **Governatori**: 3 carte a testa, se ne tiene una (scelta segreta, rivelata insieme); oppure
   **asta in PV** con n+1 carte. Tutti i 24 poteri (Politico con le sue caselle 5 e 10, Duca,
   Truffatore +1/+3, Damigella, Ereditiera, Esattore, Architetto…).
4. **Carte Fato**: una per anno, tutte le 29 carte (Il Re è malato due volte: alla seconda il Re muore
   e la partita finisce quell'anno; Situazione Perdurante; Manovra a Tenaglia con due carte Invasori…).
5. **Rinforzi determinabili**: gettoni 0,1,1,2,3,4 scelti in segreto in Inverno; quello avanzato vale PV.
   Con l'Accademia Militare il dado si dimezza per eccesso; con la Nevicata un soldato in meno e niente 0.
6. **Capricci a Corte**: le 16 tessere, una per stagione (o la variante Restaurazione).

Le scelte segrete con più persone allo stesso schermo passano da una schermata "tocca a…".

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
- Capriccio 9: si usano le icone della tessera (due cose diverse fra Oro, Legno, Pietra, soldato,
  gettone +2), che non coincidono con il testo del regolamento.
- Capricci 3 e 8: "il giocatore alla tua sinistra" è il posto successivo nell'elenco dei giocatori.
- Espansione Urbanistica: chi ha Argano o Falegnameria risparmia la merce che gli manca di più.
- Esattore: le merci arrivano alla fine del turno di costruzione di chi ha costruito.
- Duca: sposta i dadi dal Consigliere più alto che ha influenzato oltre il 12.
