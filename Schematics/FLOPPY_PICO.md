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

Stand: Schritt 1 ist fertig und im Emulator wie am Board (über den FTDI)
geprüft - BASIC (`db6502_disk.s`), `drivesim.py`, Emulator-Option `-A`. Die
Pico-Firmware (`Arduino/floppy_pico/`) ist geschrieben und kompiliert; auf dem
Mac gebaut, mit Attrappen für Laufwerk und Diskette, läuft sie im Emulator gegen
das echte BASIC (siehe „Testen ohne Laufwerk“). An Pico und Laufwerk ist sie
noch ungeprüft. Umschalter und Verdrahtung sind geplant.

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
- In Stellung „Mac“ hört der Pico weiter mit, TxD bleibt ja an GP1: Ein
  `LOAD`/`SAVE ...,8` an `drivesim.py` führt er stumm mit aus, ein SAVE landet
  dann auch auf der Diskette.

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
- **Jeder der 8 Eingänge der 74LVC07A bekommt 10 kΩ nach 3,3 V**, etwa ein
  Widerstandsnetz 8 × 10 kΩ. Bis die Firmware läuft - beim Einschalten, beim
  Reset und die ganze Zeit im BOOTSEL-Modus beim Flashen - sind alle GPIOs des
  Pico Eingänge mit Pull-down. Ohne die Pull-ups wären SELECT, MOTOR und WRGATE
  dann aktiv: Das Laufwerk liefe angewählt, und der Schreibkopf löschte die Spur
  unter sich. 10 kΩ überstimmen den Pull-down des RP2040 (etwa 50 kΩ).
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
| 26 | 720 KB READ ONLY | SAVE auf eine 720-KB-Diskette, siehe Pico-Firmware |
| 31 | SYNTAX ERROR | Befehl unbekannt |
| 33 | SYNTAX ERROR | Name ungültig |
| 52 | FILE TOO LARGE | Datei oder Listing über 64 KB |
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

**ENQ ($05), Pico → 6502**: schickt der Pico, sobald er bereit ist, etwa nach
dem Einschalten. Wartet BASIC gerade auf die erste Statuszeile, schickt es den
Befehl noch einmal - der erste kam bei niemandem an. Nach dem Listing eines
SAVE gilt ENQ nicht: BASIC wartet weiter und meldet `?DEVICE NOT PRESENT`. Am
Prompt überliest BASIC ein ENQ wie jedes Steuerzeichen.

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

`Arduino/floppy_pico/floppy_pico.ino`, ein Arduino-Sketch. Er folgt
`drivesim.py` Schritt für Schritt, mit einer Diskette statt des Ordners.

- Arduino-Pico-Core 5.5.0 (Earle Philhower), Bibliotheken Adafruit Floppy 0.6.1
  und SdFat - Adafruit Fork 2.3.102. Bauen:

  ```
  arduino-cli compile -b rp2040:rp2040:rpipico --output-dir Arduino/floppy_pico/build Arduino/floppy_pico
  ```

- Flashen: Pico mit gedrückter BOOTSEL-Taste anstecken,
  `Arduino/floppy_pico/build/floppy_pico.ino.uf2` auf das Laufwerk RPI-RP2
  ziehen - nur mit den Pull-ups oben oder bei ausgeschaltetem Laufwerk.
- `Serial1` auf GP0/GP1, 19200 8N1. Gleich nach dem Start schickt der Pico ein
  ENQ.
- `Adafruit_MFM_Floppy` erkennt 720 KB und 1,44 MB am Bootsektor, darauf
  `FatVolume`. SAVE nur auf 1,44 MB: Die Bibliothek schreibt jede Diskette, die
  sie selbst erkannt hat, mit dem Bittakt von 1,44 MB - eine 720-KB-Diskette
  wäre danach unlesbar. Dort antwortet SAVE mit `26,720 KB READ ONLY`.
- Ein Programm liegt immer ganz im RAM (64 KB): LOAD liest die Datei vor dem
  `00,OK`, SAVE schreibt erst nach dem EOT. Beim Lesen einer Spur sind die
  Interrupts eine Umdrehung lang aus; der UART verlöre dabei Bytes, aber der
  6502 wartet dann ohnehin.
- Diskettenwechsel: DSKCHG (Pin 34) gilt nur bei angewähltem Laufwerk und wird
  vor jedem Befehl gelesen. Ist es aktiv, macht der Kopf einen Schritt hin und
  zurück. Bleibt es danach aktiv, ist keine Diskette drin
  (`74,DRIVE NOT READY`), sonst wird die Diskette neu eingelesen.
- Motor aus nach 3 s ohne Befehl, außer während das Listing eines SAVE kommt.
- Das Inhaltsverzeichnis steht in der Reihenfolge der Diskette, wie bei der
  1541. Die Kopfzeile ist das Volume-Label, ohne Label „FLOPPY“. Namen, die
  nicht in 8.3 passen, und die Punkt-Dateien des Mac fehlen.
- Die Pico-LED (GP25) leuchtet, solange das Laufwerk angewählt ist.
- Die USB-Schnittstelle des Pico protokolliert jeden Befehl mit Zeiten
  (beliebiges Terminal). Ein `v` dort schaltet jedes Byte auf der Leitung und
  die Kopfschritte dazu.

## Testen ohne Laufwerk

- `Software/tools/drivesim.py` spielt das Laufwerk mit einem Ordner auf dem
  Mac, über den FTDI (Schalter auf „Mac“) - die BASIC-Seite lässt sich so am
  echten Board prüfen, bevor es den Pico gibt. Der ACIA sendet erst, wenn
  drivesim den Port offen hat (`/CTS` = RTS des FTDI), und das erste Byte danach
  geht am Mac verloren. drivesim schickt deshalb nach dem Öffnen ein ENQ, und
  BASIC wiederholt den Befehl - die Reihenfolge ist also egal. `-v` zeigt jedes
  Byte auf der Leitung.
- Der Emulator (`GeckOS-V2/arch/jp6502/emu/jp6502emu`) hängt mit `-A` den ACIA
  an ein Programm, etwa `drivesim.py --stdio`, und läuft dann in Echtzeit -
  sonst rechnet er 10 s Emulatorzeit in einem Bruchteil davon durch, und die
  Antwort des Programms kommt für BASIC zu spät.
- `Arduino/floppy_pico/host/` baut die Pico-Firmware für den Mac: Attrappen
  ersetzen Arduino-Core, Adafruit Floppy und SdFat, die Diskette ist ein
  Ordner. `make -C Arduino/floppy_pico/host test` lässt sie im Emulator gegen
  das MS-BASIC aus `Software/build/rom` laufen, in etwa einer Minute. Die Fälle
  liegen in `host/tests/`: Verzeichnis, LOAD, SAVE, Datei fehlt, Pico startet
  zu spät, keine Diskette, Schreibschutz, 720 KB, langsames Laufwerk. Jeder ist
  ein Emulator-Skript; Kommentare darin sagen, wie sich das Laufwerk verhält und
  was herauskommen muss. Adafruit Floppy am echten Laufwerk prüft das nicht.

## Schritte

1. BASIC-Seite, `drivesim.py`, Emulator-Test. *Erledigt.*
2. Umschalter einbauen, `LOAD "...",8` gegen `drivesim.py` am Mac prüfen.
3. Pico-Firmware schreiben und hier kompilieren *(erledigt)*; Pico und
   Laufwerk verdrahten, UF2 flashen.
4. Erst eine Diskette lesen, die am Mac oder PC beschrieben wurde, dann
   speichern.
