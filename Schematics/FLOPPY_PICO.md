# Diskettenlaufwerk an MS-BASIC und GeckOS: Raspberry Pi Pico als Controller

Ein PC-Diskettenlaufwerk (3,5", 34-polig) bekommt einen Raspberry Pi Pico als
eigenen Controller. MS-BASIC spricht ihn über die serielle Schnittstelle an,
wie der C64 seine 1541 über Gerät 8:

```
LOAD "HELLO.BAS",8      ein Programm laden
SAVE "HELLO.BAS",8      speichern
LOAD "$",8              das Inhaltsverzeichnis als Programm laden, dann LIST
```

Ohne `,8` bleibt alles wie bisher bei der SD-Karte.

Unter GeckOS ist das Laufwerk `c:`. GeckOS startet von dort, wenn eine Diskette
mit seinen Programmen im Laufwerk liegt, sonst wie bisher von der SD-Karte -
siehe „GeckOS-Seite“.

Stand: Pico und Laufwerk laufen am Board, vorerst mit Steckbrücken verdrahtet.
Verzeichnis, LOAD und SAVE gehen mit einer 1,44-MB-Diskette, auch mit einem
Wechsel der Diskette. `format`, 720-KB-Disketten und GeckOS sind bisher nur auf
dem Mac geprüft (siehe „Testen ohne Laufwerk“). Der Umschalter fehlt noch.

## Warum der Pico

- Die Bibliothek **Adafruit_Floppy** (RP2040 und SAMD51) liest und schreibt
  PC-Disketten mit 720 KB und 1,44 MB auf Flusswechsel-Ebene, über die PIO
  des RP2040 - unabhängig von Interrupts. Ein Blockgerät für SdFat bringt sie
  mit, FAT12 kommt damit aus `FatVolume`; die Firmware nimmt davon nur
  Capture, Decoder und Encoder, siehe Pico-Firmware.
- 264 KB RAM: ein ganzes BASIC-Programm passt hinein, so muss SAVE nie auf das
  Laufwerk warten.
- ESP32: genug Leistung, aber keine fertige Bibliothek - MFM selbst zu
  dekodieren und zu schreiben wäre ein eigenes Projekt. ESP8266: zu wenig
  Pins, keine passende Zeit-Hardware.

## Umschalter am ACIA

Der ACIA (U5) ist der einzige serielle Anschluss und hängt am FTDI für den Mac,
einem FT230X (U6), der fest auf dem Board sitzt. Mac und Laufwerk werden nie
gleichzeitig gebraucht, also ein zweipoliger Umschalter (2 × UM) am ACIA:

| | Stellung „Mac“ | Stellung „Disk“ |
|---|---|---|
| Pol A an ACIA **RxD (Pin 12)** | J2 Pin 2 (FTDI-TXD) | Pico GP0 (UART0 TX), über 1 kΩ |
| Pol B an ACIA **/CTS (Pin 9)** | J2 Pin 4 (FTDI-RTS) | GND |

**Pin 12 und 9 müssen vom Board getrennt werden.** Der FT230X bekommt seinen
Strom aus den 5 V des Boards, auch ohne USB-Kabel, und treibt RxD und /CTS
selbst; parallel dazu arbeiteten Pico-TX und FTDI-TXD gegeneinander. Ohne
Eingriff ins Board geht das mit einer zweiten DIP-28-Fassung als Zwischenstecker
zwischen Board-Fassung und ACIA: Ihre Pins 9 und 12 sind nach außen gebogen,
gehen also nicht in die Board-Fassung, und bekommen je einen Draht zum Schalter.

Alles andere liegt an J2, der 6-poligen Buchsenleiste „Optional UART Port“. Die
Namen gelten aus Sicht des ACIA, und mit dem Zwischenstecker führen Pin 2 und
Pin 4 nur noch zum FT230X:

| J2 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Leitung | TxD | RxD | /RTS | /CTS | GND | +5 V |

- ACIA **TxD (Pin 10)** bleibt am FTDI und geht zusätzlich von J2 Pin 1 über
  einen Spannungsteiler an Pico GP1 (UART0 RX, Pico-Pin 2): 2,2 kΩ in Reihe,
  3,3 kΩ nach GND, das ergibt etwa 3 V.
- GND: J2 Pin 5 an Pico-Pin 3.
- Pico TX (GP0, Pico-Pin 1): 3,3 V reichen für den ACIA, auch der FT230X treibt
  RxD nur mit 3,3 V. Die 1 kΩ sind für die Zeit, in der das Board aus ist: Am
  USB des Mac hat der Pico weiter Strom, und GP0 versorgte das Board sonst über
  den Eingang des ACIA mit.
- J2 Pin 6 (+5 V) nicht an den Pico, solange der am USB hängt - das Board
  drückte sonst Strom in den USB-Port des Mac.
- /CTS auf GND: Der ACIA sendet nur bei /CTS low; den 6502 bremsen muss der
  Pico nie.
- 19200 Baud, 8N1 - wie `_acia_init` und `basicsend.py`.
- In Stellung „Mac“ hört der Pico weiter mit, TxD bleibt ja an GP1: Ein
  `LOAD`/`SAVE ...,8` an `drivesim.py` führt er stumm mit aus, ein SAVE landet
  dann auch auf der Diskette.

Ohne Schalter ist das die Stellung „Disk“, fest verdrahtet: ACIA Pin 12 über
1 kΩ an GP0, Pin 9 an GND. Der Mac kann dann nichts mehr ans Board schicken,
hört über den FT230X aber weiter alles, was der 6502 sendet.

Pinbelegung des ACIA aus `Datasheets/R6551_Rockwell.pdf`, Bauteile und J2 aus
`Schematics/65C02_Computer`.

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
  braucht 4,7 kΩ nach 3,3 V (Empfehlung von Adafruit): Die Bibliothek schaltet
  dort keinen internen Pull-up ein, und ohne den Widerstand kommt kein
  Flusswechsel an. Die übrigen bekommen die internen Pull-ups.
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
| 21 | READ ERROR | keine Flusswechsel: nichts auf die Spur geschrieben, oder READ ohne Pull-up |
| 25 | WRITE ERROR | Schreiben fehlgeschlagen |
| 26 | WRITE PROTECT ON | Schreibschutz bei SAVE |
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
Kopfbewegung, eine neu eingelegte Diskette einlesen. Die 10 s zählen ab dem
letzten Byte, das ankam. Kommt nichts, meldet es `?DEVICE NOT PRESENT`, zum
Beispiel wenn der Schalter auf „Mac“ steht. Ctrl+C bricht das Warten ab. Das
Schreiben nach einem SAVE dauert bei einem langen Programm länger; der Pico
schickt dabei alle 2 s ein ENQ, siehe unten.

**ENQ ($05), Pico → 6502**: schickt der Pico, sobald er bereit ist, etwa nach
dem Einschalten. Wartet BASIC gerade auf die erste Statuszeile, schickt es den
Befehl noch einmal - der erste kam bei niemandem an. Nach dem Listing eines
SAVE überliest BASIC ein ENQ und wartet von vorn: So hält der Pico es hin,
solange er schreibt. Ein Pico, der in dieser Zeit neu startet, hat das Listing
verloren - sein ENQ verlängert nur das Warten bis `?DEVICE NOT PRESENT`. Am
Prompt überliest BASIC ein ENQ wie jedes Steuerzeichen.

**Dateien** sind Text mit CR LF, wie die `.BAS`-Dateien der SD-Karte - auf
dem Mac oder PC lesbar. Namensregeln wie bei der SD-Karte: die Endung gehört
dazu (`"HELLO.BAS"`).

## Protokoll für GeckOS

GeckOS lädt Programme, also Binärdaten, und hat mehrere Dateien zugleich offen.
Dafür gibt es neben den Zeilen von BASIC Rahmen mit Längenangabe. Der Pico
erkennt sie am ersten Byte, SOH ($01) - so beginnt keine Zeile von BASIC:

```
6502 -> Pico   $01, Befehl, Datei, n, n Bytes
Pico -> 6502   Fehler, n, n Bytes
```

Datei ist 0 bis 3, die Nummer, unter der der Pico eine Datei offen hält. Die
Befehle sind die des Dateisystems von GeckOS (`FS_*` in
`GeckOS-V2/include/fdefs.i65`), mit dem Namen, wie ein Programm ihn schickt,
dazu drei eigene:

| Befehl | Code | n Bytes zum Pico | Antwort |
|---|---|---|---|
| HELLO | 0 | Uhrzeit und Datum im FAT-Format, 4 Bytes | |
| FS_OPEN_RD | 1 | Name | 1 |
| FS_OPEN_WR, _OW, _AP | 2, 4, 5 | Name | 2 |
| FS_OPEN_DR | 6 | Verzeichnis oder Muster | 1 |
| FS_RENAME | 7 | alter und neuer Name | |
| FS_DELETE | 8 | Name | |
| FS_FORMAT | 9 | Name der Diskette | |
| FS_CLOSE | 11 | | |
| FS_RMDIR, FS_MKDIR | 12, 13 | Name | |
| READ | 64 | | die nächsten Bytes der Datei, bis zu 56 |
| WRITE | 65 | bis zu 128 Bytes der Datei | |

- Ein Öffnen bringt ein Byte zurück: 1 für eine Datei zum Lesen - auch ein
  Verzeichnis -, 2 für eine zum Schreiben.
- Fehler sind die Codes von GeckOS: 0 OK, -10 Dateiende (mit den letzten Bytes
  eines READ), -33 Pfad fehlt, -36 Datei fehlt, -37 Schreibschutz, -39 Diskette
  voll, -40 Verzeichnis nicht leer, -42 keine oder unlesbare Diskette. Nach dem
  Dateiende oder einem Fehler hat der Pico die Datei selbst geschlossen.
- Ein Verzeichnis liest sich wie eine Datei, Eintrag für Eintrag im Format von
  GeckOS: Länge, Datum, Art, Name in Kleinbuchstaben. Vorweg kommt der Name der
  Diskette, am Ende der freie Platz.
- Vor der Antwort schickt der Pico für jede halbe Sekunde, die er braucht, ein
  ENQ ($05). Kommt kein Byte, gibt GeckOS nach 2,5 s auf (bei 4 MHz), auf
  HELLO nach 1 s.
- Ein READ ist so kurz, dass die Antwort samt Kopf in den Empfangspuffer von
  GeckOS passt (64 Bytes). Der Pico schickt nur auf Anfrage, also geht kein
  Byte verloren, wie lange GeckOS auch nicht zum Lesen kommt.

## BASIC-Seite

- `LOAD` und `SAVE` (`db6502_sdbasic.s`): nach dem Namen ein Blick auf `,8`.
  Anderes Gerät: `?ILLEGAL QUANTITY`.
- `db6502_disk.s` (Segment `CODE`): Befehl senden, Statuszeile mit Zeitlimit
  lesen, Fehler zeigen, dann weiter in `LOAD "@"` / `SAVE "@"` hinter deren
  eigener Anzeige - das LCD zeigt den echten Dateinamen. Nach einem SAVE
  wartet `ser_endsave` auf die zweite Statuszeile.
- ROM: geschätzt 200-300 Bytes, in der Lücke bei `$E512` (siehe
  `Software/MEMORY_MAP.md`).

## GeckOS-Seite

- `fsflop` (`GeckOS-V2/arch/jp6502/fsflop.a65`, rund 540 Bytes im ROM) ist der
  Dateisystem-Server für `c:`. Er reicht die Anfragen der Programme an den
  Pico weiter und schiebt die Bytes der offenen Dateien zwischen Leitung und
  Streams hin und her, bis zu vier Dateien zugleich.
- Beim Start schickt er HELLO, mit Uhrzeit und Datum der DS3231 für die
  Zeitstempel der Dateien, die der Pico schreibt. Antwortet niemand -
  Schalter auf „Mac“, kein Pico, oder einer, der noch nicht läuft -, bleibt
  die Leitung beim seriellen Gerät, und GeckOS startet wie ohne Laufwerk. Der
  Pico muss also laufen, bevor GeckOS startet.
- Antwortet der Pico, gehört ihm die Leitung: Die Shell auf der seriellen
  Leitung entfällt, nur die Konsole hat eine.
- init startet die Shell der Konsole von `c:`. Geht das nicht - keine
  Diskette, keine `lsh` darauf -, nimmt es die von der SD-Karte, `b:`. Dafür
  haben die ROM-Einträge von init ein neues Bit, `PK_ALT`: Der Eintrag startet
  nur, wenn der davor nicht starten konnte (`INIT_ALT` in
  `GeckOS-V2/sysapps/init/init.a65`). Die Shell auf der seriellen Leitung hat
  es auch, hinter `fsflop`.
- Eine Diskette zum Starten: GeckOS von der SD-Karte starten, die Diskette
  einlegen, dann

  ```
  format c:BOOT     1,44 MB, Name BOOT - was auf der Diskette war, ist weg
  cp b:* c:         alle Programme der SD-Karte auf die Diskette
  ```

  `format` dauert etwa zwei Minuten, `cp b:* c:` gut eine Minute. Beide
  Programme liegen auf der SD-Karte (`GeckOS-V2/arch/jp6502/boot/sdcard`).
  Eine Diskette, die nur zum Speichern dient, braucht kein `lsh`.
- Tempo, 19200 Baud: Lesen etwa 1,35 KB/s - `lsh` (7,4 KB) lädt in 5,5 s -,
  Schreiben etwa 0,8 KB/s.
- Ohne Laufwerk: `make FLOPPY=-DNO_FLOPPY` in `GeckOS-V2/arch/jp6502` baut
  GeckOS wie vorher, mit rund 650 Bytes mehr Platz im ROM.

## Pico-Firmware

`Arduino/floppy_pico/floppy_pico.ino`, ein Arduino-Sketch. Er folgt
`drivesim.py` Schritt für Schritt, mit einer Diskette statt des Ordners.

- Arduino-Pico-Core 5.5.0 (Earle Philhower), Bibliotheken Adafruit Floppy 0.6.1
  und SdFat - Adafruit Fork 2.3.102. Der Core bringt ein eigenes SdFat (2.3.1)
  mit, das arduino-cli für `SdFat.h` vorzieht - ohne FAT12 und nur mit
  Partitionstabelle, also für keine Diskette. Der Sketch bindet deshalb
  `SdFat_Adafruit_Fork.h` ein, das nur der Fork hat; in der Ausgabe von
  `arduino-cli compile` steht dann bei den benutzten Bibliotheken der Fork.
  Bauen:

  ```
  arduino-cli compile -b rp2040:rp2040:rpipico --output-dir Arduino/floppy_pico/build Arduino/floppy_pico
  ```

- Flashen: Pico mit gedrückter BOOTSEL-Taste anstecken,
  `Arduino/floppy_pico/build/floppy_pico.ino.uf2` auf das Laufwerk RPI-RP2
  ziehen - nur mit den Pull-ups oben oder bei ausgeschaltetem Laufwerk.
- `Serial1` auf GP0/GP1, 19200 8N1. Gleich nach dem Start schickt der Pico ein
  ENQ.
- Spuren und Sektoren für `FatVolume` liefert eine eigene Schicht (`Disk`)
  statt `Adafruit_MFM_Floppy`. Deren Spur-Encoder bekommt in Version 0.6.1
  keine Einstellungen - Lückengrößen und Füllbyte kommen von irgendwo vom
  Stack, jedes Schreiben wäre ein Glücksspiel (auf `main` behoben, noch ohne
  Release) -, und eine 720-KB-Diskette schriebe sie mit dem Bittakt von
  1,44 MB. Gelesen wird mit Capture und Decoder der Bibliothek, geschrieben mit
  dem Encoder aus ihrer `mfm_impl.h`, sauber eingestellt. 720 KB und 1,44 MB
  erkennt die Firmware am Bootsektor und liest und schreibt beide.
- Sie hält drei Spuren im RAM, 9 KB je Spur. Spur 0 hat einen Platz für jede
  Seite - Bootsektor, FATs und Verzeichnis liegen dort, bei 720 KB wie bei
  1,44 MB -, alle anderen Spuren teilen sich den dritten. Geschriebene Sektoren
  gehen dort hinein; eine Spur geht ganz zurück auf die Diskette, wenn ihr
  Platz gebraucht wird oder SdFat synchronisiert: erst die Daten, dann FAT und
  Verzeichnis. Spur 0 bleibt von Befehl zu Befehl gehalten, bis die Diskette
  herauskommt - ein zweites `LOAD "$",8` liest nichts mehr.
- Von einer Spur, in die geschrieben wird, liest die Firmware nur, was fehlt,
  und erst, wenn ein Lesezugriff es braucht oder die Spur zurückgeht. Den Rest
  legt der Decoder neben die geschriebenen Sektoren, ohne sie anzurühren. Eine
  Spur, die ein SAVE ganz neu füllt, wird gar nicht gelesen. Ein SAVE von 5 KB
  kostet so 1 bis 3 gelesene Umdrehungen statt 6 bis 8, eins von 40 KB eine
  statt 7.
- Die Bibliothek wartet ohne Zeitlimit: beim Lesen, mit abgeschalteten
  Interrupts, auf Flusswechsel, beim Schreiben auf den Indexpuls. Der Pico
  hinge dann für immer. Deshalb prüft die Firmware vor jedem Lesen 2 ms lang,
  ob auf READ Flanken kommen - sonst `21,READ ERROR` und im Protokoll
  „no flux“ -, und vor jedem Schreiben, ob die Diskette noch drin ist.
- Ein Programm liegt immer ganz im RAM (64 KB): LOAD liest die Datei vor dem
  `00,OK`, SAVE schreibt erst nach dem EOT. Beim Lesen einer Spur sind die
  Interrupts eine Umdrehung lang aus; der UART verlöre dabei Bytes, aber der
  6502 wartet dann ohnehin.
- Unter GeckOS gehen Dateien stückweise über die Leitung, gleich wie groß.
  Eine geschriebene Datei kommt mit FS_CLOSE ganz auf die Diskette, samt FAT
  und Verzeichnis, ebenso jedes DELETE, RENAME, MKDIR und RMDIR. Zeitstempel:
  die Uhr aus HELLO, weitergezählt; ohne HELLO, unter BASIC, 1.1.2026 12:00.
- Diskettenwechsel: DSKCHG (Pin 34) gilt nur bei angewähltem Laufwerk und wird
  vor jedem Befehl gelesen. Ist es aktiv, macht der Kopf einen Schritt hin und
  zurück. Bleibt es danach aktiv, ist keine Diskette drin
  (`74,DRIVE NOT READY`), sonst wird die Diskette neu eingelesen. Offene
  Dateien von GeckOS sind dann geschlossen.
- Motor aus nach 3 s ohne Befehl, außer während das Listing eines SAVE kommt.
- Der Kopf macht alle 4 ms einen Schritt. Adafruit Floppy wartet ab Werk
  zweimal `step_delay_us / 1000 + 1` ms je Schritt, mit 10000 also 22 ms; die
  Firmware setzt 1000. Ein 3,5"-Laufwerk schafft 3 ms, 2 ms - jeder Wert unter
  1000 - wären zu schnell.
- Das Inhaltsverzeichnis steht in der Reihenfolge der Diskette, wie bei der
  1541. Die Kopfzeile ist das Volume-Label, ohne Label „FLOPPY“. Namen, die
  nicht in 8.3 passen, und die Punkt-Dateien des Mac fehlen.
- Die Pico-LED (GP25) leuchtet, solange das Laufwerk angewählt ist.
- Die USB-Schnittstelle des Pico protokolliert jeden Befehl mit Zeiten
  (beliebiges Terminal) und nimmt eigene Befehle an, je eine Zeile mit Enter:
  `v` schaltet jedes Byte auf der Leitung und die Kopfschritte dazu,
  `format [720] [NAME]` formatiert die Diskette, `dump SEKTOR` zeigt einen
  Sektor als Hexdump. Beim Einlesen einer Diskette stehen die Werte ihres
  Bootsektors im Protokoll.
- **Formatieren**: `format NAME` für 1,44 MB, `format 720 NAME` für 720 KB.
  Jede Spur wird neu geschrieben, samt Sektor-Headern - auch eine gelöschte
  Spur 0 kommt so wieder -, und gleich zurückgelesen. Danach ist die Diskette
  leer wie nach `FORMAT A:`, NAME (bis 11 Zeichen) ist ihr Volume-Label. Das
  dauert etwa zwei Minuten. Der Befehl wartet, bis der 6502 eine Sekunde lang
  nichts schickt; was BASIC währenddessen sendet, verwirft der Pico.

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
- `Arduino/floppy_pico/host/` baut die Pico-Firmware für den Mac, mit dem
  SdFat und dem MFM-Code des Pico-Builds aus den Arduino-Bibliotheken. Nur das
  Laufwerk ist eine Attrappe: Sie behält die Flusswechsel jeder geschriebenen
  Spur, eine Umdrehung je Spur, und dekodiert mit dem Decoder von Adafruit
  Floppy - was ein Test liest und schreibt, ist eine FAT12-Diskette in MFM. Die
  Diskette beginnt mit den Dateien eines Ordners und gibt am Ende alles an ihn
  zurück. `make -C Arduino/floppy_pico/host test` lässt die Firmware im
  Emulator gegen das MS-BASIC aus `Software/build/rom` und gegen GeckOS laufen,
  in gut einer Minute. Mit `-r` kommen die Bytes der Leitung im Takt der
  Baudrate, ob der 6502 sie abholt oder nicht; verlorene zählt der Emulator.
  Die Fälle liegen in `host/tests/`. BASIC: Verzeichnis, LOAD, SAVE, Datei
  fehlt, Pico startet zu spät, keine Diskette, keine Flusswechsel,
  Schreibschutz, 720 KB, langsames Laufwerk, Schreiben länger als 10 s,
  Formatieren und Hexdump über USB. GeckOS: Start von der Diskette, ohne
  Diskette, ohne Pico, `format` und `cp` Byte für Byte, Umleiten, Umbenennen,
  Verzeichnisse, Löschen und Fehler. Jeder Fall ist ein Emulator-Skript;
  Kommentare darin sagen, wie sich das Laufwerk verhält und was herauskommen
  muss. Adafruit Floppy am echten Laufwerk prüft das nicht.

## Schritte

1. BASIC-Seite, `drivesim.py`, Emulator-Test. *Erledigt.*
2. Umschalter einbauen, `LOAD "...",8` gegen `drivesim.py` am Mac prüfen.
3. Pico-Firmware schreiben und hier kompilieren, Pico und Laufwerk verdrahten,
   UF2 flashen. *Erledigt.*
4. Erst eine Diskette lesen, die am Mac oder PC beschrieben wurde, dann
   speichern. *Erledigt.*
5. GeckOS: Laufwerk `c:`, Start von der Diskette, `format` und `cp`. Im
   Emulator geprüft, am Board noch nicht.
