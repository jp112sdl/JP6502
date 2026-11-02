# Diskettenlaufwerk an MS-BASIC: Raspberry Pi Pico als Controller

Ein PC-Diskettenlaufwerk (3,5", 34-polig) bekommt einen Raspberry Pi Pico als
eigenen Controller. MS-BASIC spricht ihn über die serielle Schnittstelle an,
wie der C64 seine 1541 über Gerät 8:

```
LOAD "HELLO.BAS",8      ein Programm laden
SAVE "HELLO.BAS",8      speichern
LOAD "$",8              das Inhaltsverzeichnis als Programm laden, dann LIST
```

Ohne `,8` bleibt alles wie bisher bei der SD-Karte.

Stand: Schritt 1 ist fertig und im Emulator geprüft - BASIC (`db6502_disk.s`),
`drivesim.py`, Emulator-Option `-A`. Umschalter, Pico und Laufwerk sind geplant.

## Warum der Pico

- Die Bibliothek **Adafruit_Floppy** (RP2040 und SAMD51) liest und schreibt
  PC-Disketten mit 720 KB und 1,44 MB auf Flusswechsel-Ebene, über die PIO
  des RP2040 - unabhängig von Interrupts. `Adafruit_MFM_Floppy` ist ein
  Blockgerät für SdFat (`readSectors`, `writeSectors`), FAT12 kommt damit aus
  `FatVolume`. Beispiele `03_fat_test` und `05_mfm_write_test`.
- 264 KB RAM: ein ganzes BASIC-Programm passt hinein, so muss SAVE nie auf das
  Laufwerk warten.
- ESP32: genug Leistung, aber keine fertige Bibliothek - MFM selbst zu
  dekodieren und zu schreiben wäre ein eigenes Projekt. ESP8266: zu wenig
  Pins, keine passende Zeit-Hardware.

## Umschalter am ACIA

Der ACIA ist der einzige serielle Anschluss und hängt am FTDI für den Mac.
Mac und Laufwerk werden nie gleichzeitig gebraucht, also ein zweipoliger
Umschalter (2 × UM) am R6551:

| | Stellung „Mac“ | Stellung „Disk“ |
|---|---|---|
| Pol A an ACIA **RxD (Pin 12)** | FTDI-TXD | Pico GP0 (UART0 TX) |
| Pol B an ACIA **/CTS (Pin 9)** | FTDI-RTS | GND |

- ACIA **TxD (Pin 10)** bleibt am FTDI und geht zusätzlich über einen
  Spannungsteiler an Pico GP1 (UART0 RX): 2,2 kΩ in Reihe, 3,3 kΩ nach GND,
  das ergibt etwa 3 V.
- Pico TX (3,3 V) direkt an den ACIA: reicht für dessen TTL-Eingang.
- /CTS auf GND: Der ACIA sendet nur bei /CTS low; den 6502 bremsen muss der
  Pico nie.
- 19200 Baud, 8N1 - wie `_acia_init` und `basicsend.py`.

Pinbelegung des R6551 aus `Datasheets/R6551_Rockwell.pdf`.

## Pico an das Laufwerk

PC-Belegung, alle ungeraden Pins GND. Die GPIOs sind die Pico-Vorgaben aus den
Beispielen von Adafruit_Floppy. Gerades Kabel: Das Laufwerk ist ab Werk als
„DS1“ gejumpert und reagiert auf Pin 12 und 16.

| Signal | Floppy-Pin | Richtung | Pico |
|---|---|---|---|
| DENSITY | 2 | zum Laufwerk | GP2 |
| INDEX | 8 | vom Laufwerk | GP3 |
| SELECT (Drive B) | 12 | zum Laufwerk | GP4 |
| MOTOR (Motor B) | 16 | zum Laufwerk | GP5 |
| DIR | 18 | zum Laufwerk | GP6 |
| STEP | 20 | zum Laufwerk | GP7 |
| WRDATA | 22 | zum Laufwerk | GP8 |
| WRGATE | 24 | zum Laufwerk | GP9 |
| TRK0 | 26 | vom Laufwerk | GP10 |
| PROT | 28 | vom Laufwerk | GP11 |
| READ | 30 | vom Laufwerk | GP12 |
| SIDE | 32 | zum Laufwerk | GP13 |
| DSKCHG | 34 | vom Laufwerk | GP14 |

- **Zum Laufwerk** (8 Leitungen) über **2 × 74LVC07A**: offene Ausgänge, die
  nur nach GND ziehen, versorgt mit 3,3 V, an den Ausgängen 5-V-fest. Ohne sie
  hinge der Pico über die Pull-ups im Laufwerk an 5 V. Nicht invertierend, die
  Software merkt nichts davon.
- **Vom Laufwerk** direkt an den Pico, das Laufwerk zieht nur nach GND. READ
  bekommt 4,7 kΩ nach 3,3 V (Empfehlung von Adafruit), die übrigen die
  internen Pull-ups.
- **Strom**: 5 V, beim Anlaufen bis etwa 1 A - besser ein eigenes Netzteil.
  GND von Laufwerk, Pico und Board verbinden.
- Pico-LED (GP25) leuchtet bei Laufwerkszugriffen.

## Protokoll

Es erweitert das Zeilenprotokoll von `LOAD "@"` / `SAVE "@"`
(`Software/common/source/db6502_serial.s`): Der Pico übernimmt die Rolle von
`basicsend.py` und `basicrecv.py` und bekommt vorweg einen Befehl.

**Befehle, 6502 → Pico**, je eine Zeile mit CR am Ende. Der Name steht in der
11-stelligen FAT-Form, die BASIC für die SD-Karte ohnehin baut - acht Zeichen
Name, drei Zeichen Endung, mit Leerzeichen aufgefüllt, ohne Punkt:

```
L NAME    BAS     LOAD "NAME.BAS",8
S NAME    BAS     SAVE "NAME.BAS",8
$                 LOAD "$",8
```

**Antwort, Pico → 6502**: eine Statuszeile mit CR am Ende, im Stil der 1541:

| Code | Text | wann |
|---|---|---|
| 00 | OK | |
| 20 | READ ERROR | Sektor nicht lesbar |
| 25 | WRITE ERROR | Schreiben fehlgeschlagen |
| 26 | WRITE PROTECT ON | Schreibschutz bei SAVE |
| 31 | SYNTAX ERROR | Befehl unbekannt |
| 33 | SYNTAX ERROR | Name ungültig |
| 62 | FILE NOT FOUND | |
| 72 | DISK FULL | |
| 74 | DRIVE NOT READY | keine Diskette |

Alles außer `00` zeigt BASIC als `?62,FILE NOT FOUND` auf Bildschirm und LCD.

**LOAD**: Nach `00,OK` folgt genau der Ablauf von `LOAD "@"`:

```
6502 -> Pico   ACK ($06)    bereit für eine Zeile
Pico -> 6502   Text + CR    eine BASIC-Zeile, höchstens 78 Zeichen
...
Pico -> 6502   EOT ($04)    das war die letzte
6502 -> Pico   CAN ($18)    abgebrochen (Ctrl+C, fehlerhafte Zeile)
```

Leere Zeilen schickt der Pico nicht - auf eine leere Zeile antwortet BASIC
nicht mit ACK. Wartet BASIC zu lange auf eine Zeile, wiederholt es sein ACK;
der Pico verwirft angesammelte ACKs vor jeder Zeile, wie `basicsend.py`.

**`$`**: wie LOAD, der Pico baut das Inhaltsverzeichnis als BASIC-Zeilen im
selben Format wie die SD-Karte - danach `LIST`, wie beim C64:

```
0 "FLOPPY"
1 "HELLO.BAS        3"
2 "SNAKE.BAS       14"
3 "2713 BLOCKS FREE"
```

Name auf 13 Zeichen aufgefüllt, Größe in Blöcken zu 512 Bytes, fünfstellig
rechtsbündig.

**SAVE**: Nach `00,OK` folgt der Ablauf von `SAVE "@"`: das Listing, wie
`LIST` es ausgibt (Zeilen mit CR LF), am Ende EOT. Der Pico sammelt alles im
RAM, schreibt erst nach dem EOT auf die Diskette und schickt dann eine zweite
Statuszeile. Bricht BASIC ab (Ctrl+C), kommt statt EOT ein CAN - der Pico
verwirft dann alles und antwortet nicht.

**Zeiten**: BASIC wartet bis etwa 10 s auf eine Statuszeile - Motoranlauf,
Kopfbewegung, eine neu eingelegte Diskette einlesen, nach SAVE das Schreiben.
Kommt nichts, meldet es `?DEVICE NOT PRESENT`, zum Beispiel wenn der Schalter
auf „Mac“ steht. Ctrl+C bricht das Warten ab.

**Dateien** sind Text mit CR LF, wie die `.BAS`-Dateien der SD-Karte - auf
dem Mac oder PC lesbar. Namensregeln wie bei der SD-Karte: die Endung gehört
dazu (`"HELLO.BAS"`).

## BASIC-Seite

- `LOAD` und `SAVE` (`db6502_sdbasic.s`): nach dem Namen ein Blick auf `,8`.
  Anderes Gerät: `?ILLEGAL QUANTITY`.
- `db6502_disk.s` (Segment `CODE`): Befehl senden, Statuszeile mit Zeitlimit
  lesen, Fehler zeigen, dann weiter in `LOAD "@"` / `SAVE "@"` hinter deren
  eigener Anzeige - das LCD zeigt den echten Dateinamen. Nach einem SAVE
  wartet `ser_endsave` auf die zweite Statuszeile.
- ROM: geschätzt 200-300 Bytes, in der Lücke bei `$E512` (siehe
  `Software/MEMORY_MAP.md`).

## Pico-Firmware

`Arduino/floppy_pico/`, ein Arduino-Sketch:

- Arduino-Pico-Core (Earle Philhower), Bibliotheken Adafruit_Floppy und SdFat
  (Adafruit-Fork).
- `Adafruit_MFM_Floppy` mit automatischer Erkennung von 720 KB und 1,44 MB,
  darauf `FatVolume`.
- `Serial1` auf GP0/GP1, 19200 8N1; die USB-Schnittstelle des Pico dient nur
  als Protokoll für die Fehlersuche.
- Diskettenwechsel (DSKCHG): neu einlesen. Motor nach einigen Sekunden Ruhe
  aus.
- Flashen: UF2-Datei, Pico mit gedrückter BOOTSEL-Taste anstecken, Datei auf
  das Laufwerk ziehen.

## Testen ohne Laufwerk

- `Software/tools/drivesim.py` spielt das Laufwerk mit einem Ordner auf dem
  Mac, über den FTDI (Schalter auf „Mac“) - die BASIC-Seite lässt sich so am
  echten Board prüfen, bevor es den Pico gibt. Der ACIA sendet erst, wenn
  drivesim den Port offen hat (`/CTS` = RTS des FTDI); BASIC schiebt den Befehl
  während der zehn Sekunden Wartezeit immer wieder an, die Reihenfolge ist also
  egal. `-v` zeigt jedes Byte auf der Leitung.
- Der Emulator (`GeckOS-V2/arch/jp6502/emu/jp6502emu`) hängt mit `-A` den ACIA
  an ein Programm, etwa `drivesim.py --stdio`.

## Schritte

1. BASIC-Seite, `drivesim.py`, Emulator-Test. *Erledigt.*
2. Umschalter einbauen, `LOAD "...",8` gegen `drivesim.py` am Mac prüfen.
3. Pico-Firmware schreiben und hier kompilieren; Pico und Laufwerk
   verdrahten, UF2 flashen.
4. Erst eine Diskette lesen, die am Mac oder PC beschrieben wurde, dann
   speichern.
