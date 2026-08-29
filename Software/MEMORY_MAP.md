# DB6502 / wooandy — Memory Map

Stand: 2026-08-19. Abgeleitet aus `common/firmware.ext.cfg`, `common/load.cfg`
und den ld65-Mapfiles des vollständigen Builds (cc65 V2.19).
Referenz-Build: `rom/os1` mit `ADDRESS_MODE=ext` (Default).
Alle Pfadangaben sind relativ zu `Software/`.

---

## 1. Gesamtsystem (64K Adressraum)

| Bereich | Von | Bis | Größe | Inhalt |
|---|---|---|---|---|
| ZP | `$0000` | `$00FF` | 256 | Zero Page |
| STACK | `$0100` | `$01FF` | 256 | 6502 Hardware-Stack |
| SYS_RAM | `$0200` | `$09FF` | 2048 | Firmware-RAM (`SYSRAM` + `BSS`) |
| SD_RAM | `$0A00` | `$0BFF` | 512 | `SDBUF` — Sektorpuffer für BASIC-`SAVE`, page-aligned |
| FAT_RAM | `$0C00` | `$0DFF` | 512 | `FATBUF` — FAT32-Sektor-Workspace, page-aligned |
| BAS_RAM | `$0E00` | `$0FFF` | 512 | MS-BASIC Zeileneingabe (Guard-Page + `INPUTBUFFER`) |
| USERRAM | `$1000` | `$7FFF` | 28672 | Ladebereich + User-RAM + C-Stack |
| *(frei/unbelegt)* | `$8000` | `$807F` | 128 | kein Baustein dekodiert |
| VDP | `$8080` | `$80FF` | 128 | TMS9918: `$8080` VRAM, `$8081` Register |
| *(frei)* | `$8100` | `$81FF` | 256 | — |
| VIA3 | `$8200` | `$83FF` | 512 | Keyboard + SD (Register `$8200`–`$820F`) |
| ACIA | `$8400` | `$87FF` | 1024 | R6551 (Register `$8400`–`$8403`) |
| VIA2 | `$8800` | `$8FFF` | 2048 | Sound + LED + D-Pad (Reg. `$8800`–`$880F`) |
| VIA1 | `$9000` | `$9FFF` | 4096 | LCD (Register `$9000`–`$900F`) |
| ROM | `$A000` | `$FFFF` | 24576 | EEPROM-Code |

EEPROM-Image (AT28C256, 32K) = `$8000`–`$FFFF`.
`$8000`–`$9FFF` wird von der `FILLER`-Area mit `$EA` gefüllt (I/O-Schatten, nie gelesen).

---

## 2. Zero Page — `$0000`–`$00FF`

| Von | Bis | Bytes | Quelle | Inhalt |
|---|---|---|---|---|
| `$0000` | `$004E` | 79 | `common/source/zeropage.s` | cc65-Runtime (`c_sp`,`sreg`,`regsave`,`ptr1..4`,`tmp1..4`) + System-Variablen |
| `$004F` | `$0055` | 7 | `common/source/modem.s` | `crc`,`block_number`,`first_block_flag`,`memory_pointer`,`delay_counter` |
| `$0056` | `$0057` | 2 | `common/source/sd.s` | `memory_pointer` (2. Instanz) |
| `$0058` | `$00FF` | **168** | — | **frei** |

Aufteilung von `zeropage.s` (`$00`–`$4C`):

| Offset | Bytes | Symbol |
|---|---|---|
| `$00` | 2 | `c_sp` / `sp` (cc65 C-Stack-Pointer) |
| `$02` | 2 | `sreg` |
| `$04` | 4 | `regsave` |
| `$08` | 8 | `ptr1`–`ptr4` |
| `$10` | 4 | `tmp1`–`tmp4` |
| `$14` | 3 | `lcd_temp_char1..3` |
| `$17` | 1 | `acia_conn` |
| `$18` | 4 | `acia_rx_rptr/wptr`, `acia_tx_rptr/wptr` |
| `$1C` | 3 | `keyboard_conn/rptr/wptr` |
| `$1F` | 1 | `tty_config` |
| `$20` | 4 | `system_break_flag/address/sp` |
| `$24` | 3 | `user_break_address/sp` |
| `$27` | 2 | `user_irq_address` |
| `$29` | 6 | `vdp_buffer_address`, `vdp_vram_address`, `vdp_char_count` |
| `$2F` | 6 | `zp_sd_address`, `zp_sd_currentsector` |
| `$35` | 26 | `zp_fat32_variables` |

Bei MS-BASIC (`rom/microsoft_basic`) schiebt sich `basic_zp.s` dazwischen: `$004F`–`$00C7`
(121 Bytes), danach `modem.s` `$00C8`–`$00CE` und `sd.s` `$00CF`–`$00D0`.
ZP-Ende dort `$00D0`, frei `$00D1`–`$00FF` (47 Bytes).

---

## 3. System-RAM — `$0200`–`$0FFF`

### 3.1 Segment `SYSRAM` (`common/source/sysram_map.s`), `$0200`–`$0813`

| Von | Bis | Bytes | Symbol |
|---|---|---|---|
| `$0200` | `$02FF` | 256 | `acia_rx_buffer` |
| `$0300` | `$03FF` | 256 | `acia_tx_buffer` |
| `$0400` | `$043F` | 64 | `keyboard_buffer` |
| `$0440` | `$0453` | 20 | `lcd_line_buffer` |
| `$0454` | `$0813` | 960 | `text_screen_buffer` (VDP 40×24) |

Bei `rom/microsoft_basic` hängt MS-BASIC weitere 64 Bytes an dasselbe Segment an
(`db6502_extra.s`), sodass `SYSRAM` dort bis `$0853` reicht:

| Von | Bis | Bytes | Symbol |
|---|---|---|---|
| `$0814` | `$0853` | 64 | `TXTBUFFER` — zugleich `STACK2`, der String-Deskriptor-Stack |

### 3.2 Segment `BSS`

`rom/os1`: `$0814`–`$09D0` (445 Bytes).

<!-- mapdoc: os1 BSS -->

| Von | Bis | Bytes | Modul |
|---|---|---|---|
| `$0814` | `$0817` | 4 | `shell.o` |
| `$0818` | `$0893` | 124 | `monitor.o` |
| `$0894` | `$091F` | 140 | `modem.o` (`recv_buffer`) |
| `$0920` | `$0924` | 5 | `utils.o` |
| `$0925` | `$0926` | 2 | `vdp_text_mode.o` (`vdp_line`,`vdp_char_pos`) |
| `$0927` | `$0934` | 14 | `tty.o` |
| `$0935` | `$093C` | 8 | `parse.o` |
| `$093D` | `$09AC` | 112 | `menu.o` (`line_buffer` 32, `tokenize_buffer` 64, +16) |
| `$09AD` | `$09D0` | 36 | `sd.o` (Parameter + `sd_dirent*`) |

`rom/microsoft_basic`: `$0854`–`$0990` (317 Bytes).

Die Zustandsvariablen von `db6502_sdbasic.s` liegen bewusst **nicht** hier, sondern in
`BAS_RAM` (Abschnitt 3.5). `BSS` wird von allen Bibliotheksmodulen geteilt, und jedes Byte,
das `msbasic.o` hier belegt, verschiebt `vdp_line`/`vdp_char_pos` und alles dahinter.

Frei bis `$09FF` — darüber beginnt `SD_RAM`, ein Überlauf ist ein ld65-Fehler.

### 3.3 `SD_RAM` — `$0A00`–`$0BFF`

Segment `SDBUF` aus `common/source/db6502_sdbasic.s`: `sd_sectorbuffer`, der Sektorpuffer,
in dem `SAVE` das LIST-Ergebnis sammelt. Kann sich `fat32_workspace` **nicht** teilen —
`fat32_writenextsector` liest beim Weiterlaufen der Cluster-Kette FAT-Sektoren dorthin und
würde die Nutzdaten überschreiben. Nur im MS-BASIC-Build belegt.

### 3.4 `FAT_RAM` — `$0C00`–`$0DFF`

Segment `FATBUF`, definiert in `common/source/sd.s`. Enthält `fat32_workspace` (512 Bytes,
page-aligned) = `fat32_readbuffer` aus `libfat32.s`. Nur belegt, wenn `sd.o` gelinkt wird.

### 3.5 `BAS_RAM` — `$0E00`–`$0FFF`

<!-- mapdoc: microsoft_basic BASBUF -->

| Von | Bis | Bytes | Inhalt |
|---|---|---|---|
| `$0E00` | `$0E62` | 99 | Segment `BASBUF`, Teil aus `msbasic.o`: Zustandsvariablen von `db6502_sdbasic.s` (`sd_loadmode`, `sd_savemode`, `sd_fatname`, …), `start_magic`, Zustand der Grafikbefehle und des Grafiktexts |
| `$0E63` | `$0E98` | 54 | Segment `BASBUF`, Teil aus `sd.o`: Variablen des allozierenden Schreibpfads in `libfat32.s` (`fat32_partstart`, `fat32_fatsize`, `fat32_maxcluster`, `fat32_scancluster`, …) |
| `$0E69` | `$0EFB` | 147 | ungenutzt |
| `$0EFC` | `$0EFF` | 4 | Scratch von `PUT_NEW_LINE`: Link-Pointer und Zeilennummer, geschrieben als `INPUTBUFFER-4` … `INPUTBUFFER-1` (`program.s:253`, `program.s:267`, `input.s:143`) |
| `$0F00` | `$0FFF` | 256 | `INPUTBUFFER` |

`INPUTBUFFER` bleibt eine Assemblierzeit-Konstante in `defines_db6502.s` (`defines.s` wertet
sie in `.if` aus und bildet `INPUTBUFFERX = INPUTBUFFER & $FF00`); die Übereinstimmung mit
der Memory-Area wird per `.assert` gegen `__BAS_RAM_START__ + $0100` zur Linkzeit geprüft.

Die Guard-Page darunter ist nicht optional: bei `INPUTBUFFER = $0E00` lagen jene vier
Scratch-Bytes auf den letzten vier Bytes des FAT32-Sektorpuffers.

Dass die FAT32-Schreibvariablen hier statt im `BSS` liegen, hat denselben Grund wie die
Lage von `SDCODE` (Abschnitt 5.2): `sd.o` ist das letzte Modul, das zum `BSS` beiträgt,
und alles, was dort hinzukommt, verschiebt die Variablen von `sd.s` — womit sich die
Operanden im bereits verifizierten `CODE` ändern würden. `db6502_sdbasic.s` prüft per
`.assert`, dass `BASBUF` nicht über `INPUTBUFFER-4` hinauswächst.

**`BASBUF` wird nie genullt, und das ist Absicht.** Genau darauf beruht
`start_magic`: eine Signatur, die einen Reset von einem Einschalten
unterscheidet, funktioniert nur, wenn niemand die Seite beim Start löscht.
Der Preis ist, dass **jede** neue Variable hier nach dem Einschalten Zufall
enthält, bis etwas sie schreibt — und eine Variable, die Verhalten steuert,
steuert es dann in 255 von 256 Fällen falsch.

Zweimal zugeschlagen: `_start_msbasic` setzt `sd_loadmode` und `sd_savemode`
von Hand auf null, mit genau dieser Begründung im Kommentar. Und `gtx_active`,
das entscheidet, ob Zeichen in die Bitmap gehen, wurde am 25.08.2026 zwar in
`start_select` genullt — aber `standalone.s` druckt den Banner davor, und der
lief damit quer über den Zeichensatz. Seitdem hängt das Nullen an
`gtx_tty_init`, das anstelle von `_tty_init` gerufen wird, also vor dem ersten
ausgegebenen Zeichen.

Wer hier etwas anlegt, das gelesen wird, bevor es geschrieben wurde, muss sich
überlegen, wo es initialisiert wird — und ob diese Stelle wirklich vor der
ersten Benutzung liegt.

---

## 4. USERRAM / Ladebereich — `$1000`–`$7FFF`

Firmware-Sicht (`firmware.ext.cfg`): `USERRAM = $1000` + `$7000`.
Loadable-Sicht (`load.cfg`):

| Von | Bis | Größe | Inhalt |
|---|---|---|---|
| `$1000` | `$30FE` | 8447 | `LOADAREA` — `STARTUP`/`CODE`/`RODATA`/`RODATA_PA` des Loadable-Moduls |
| `$30FF` | `$80FE` | 20480 | `USERRAM` — `BSS`/`DATA` des Moduls (**Konfig-Fehler, siehe unten**) |
| ↓ | `$8000` | — | cc65 C-Stack, wächst abwärts (Init in `core.s:62`) |

`_process_run` (`rom/os1/shell.s:120`) springt fest nach `$1000`.
`common/loadtrim.py` schreibt fest `$1000` als XMODEM-Ladeadresse in Byte 0/1.

MS-BASIC `RAMSTART2 = __USERRAM_START__` → `$1000` (ROM-Build) bzw. `$30FF` (Loadable).

---

## 5. ROM — `$A000`–`$FFFF` (Build `rom/os1`)

Die beiden ROM-Tabellen und die zwei Segmenttabellen oben werden von
`make mapdoc` gegen die Mapfiles geprüft; die `mapdoc:`-Kommentare darüber
sagen dem Prüfer, welcher Build gemeint ist.

<!-- mapdoc: os1 rom -->

| Von | Bis | Bytes | Segment |
|---|---|---|---|
| `$A000` | `$CD36` | 11575 | `CODE` |
| `$CD37` | `$E026` | 4848 | `RODATA` |
| `$E027` | `$E0FF` | 217 | frei |
| `$E100` | `$E2FF` | 512 | `RODATA_PA` (XMODEM-CRC-Tabellen, page-aligned) |
| `$E300` | `$E6FF` | 1024 | frei |
| `$E700` | `$E853` | 340 | `EXTCODE` — `os1_init` sowie die Anteile aus `vdp.o` und `sd.o` |
| `$E854` | `$EBFF` | 940 | frei |
| `$EC00` | `$F37D` | 1918 | `SDCODE` — getakteter VDP-Kaltstart und der allozierende Schreibpfad aus `libfat32.s` |
| `$F37E` | `$F7FF` | 1154 | frei |
| `$F800` | `$F8A1` | 162 | `SYSCALLS` (feste Sprungtabelle für Loadables) |
| `$F8A2` | `$F8FF` | 94 | frei (Reserve für ein wachsendes `SYSCALLS`) |
| `$F900` | `$F90B` | 12 | `EXTCODE2` — `gtx_stub.s`, die vier Durchreichen für ROMs ohne Bitmap |
| `$F90C` | `$FFF9` | 1774 | frei |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` — NMI `$0000`, RESET `init`, IRQ `_interrupt_handler` |

ROM frei gesamt 5203 Bytes von 24576.

### 5.1 Build `rom/microsoft_basic`

<!-- mapdoc: microsoft_basic rom -->

| Von | Bis | Bytes | Segment |
|---|---|---|---|
| `$A000` | `$A002` | 3 | `STARTUP` (`jmp init`) |
| `$A003` | `$DA92` | 14992 | `CODE` |
| `$DA93` | `$E118` | 1670 | `RODATA` (u. a. VDP-Zeichensatz + Registertabelle) |
| `$E119` | `$E2E9` | 465 | `BAS_VEC` / `BAS_KEY` / `BAS_ERR` — `BAS_KEY` bei 277 Bytes, die 256er-Grenze ist aufgehoben, siehe 5.3 |
| `$E2EA` | `$E6FF` | 1046 | frei — hier lag `RODATA_PA`, siehe 5.4 |
| `$E700` | `$EBE7` | 1256 | `EXTCODE` — Panel, Laufwerks-LED, Fehlertexte, FSInfo-Buchführung, `BLOCKS FREE`, Kaltstart-Leuchte, `SOUND` |
| `$EBE8` | `$EBFF` | 24 | frei |
| `$EC00` | `$F7DA` | 3035 | `SDCODE` — Rumpf von `db6502_sdbasic.s`, `CLS`, getakteter VDP-Kaltstart, allozierender Schreibpfad aus `libfat32.s` |
| `$F7DB` | `$F7FF` | 37 | frei |
| `$F800` | `$F8A1` | 162 | `SYSCALLS` |
| `$F8A2` | `$F8FF` | 94 | frei (Reserve für ein wachsendes `SYSCALLS`) |
| `$F900` | `$FF21` | 1570 | `EXTCODE2` — `COLOR`, `SCREEN`, `PLOT`, `LINE`, `CIRCLE`, `SPRITE`, `VPOKE`, `KEY`, Text im Grafikmodus samt Bildlauf, Kalt-/Warmstart-Auswahl, Seitenlogik der Schlüsselworttabelle, siehe 5.1.1 und 5.3 |
| `$FF22` | `$FFF9` | 216 | frei |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` |

ROM frei gesamt 1417 Bytes von 24576.

#### 5.1.1 `EXTCODE2` — der dritte Codeblock

`EXTCODE2` liegt mit `offset=$5900` fest hinter `SYSCALLS` und ist die erste
Belegung des Bereichs `$F8A2`–`$FFF9`, der auf dieser Platine bis dahin nie
benutzt wurde. Die 94 Bytes zwischen `SYSCALLS` und `$F900` bleiben absichtlich
frei: `SYSCALLS` ist eine feste Sprungtabelle, an der Loadables hängen, und die
darf wachsen können, ohne dass etwas dahinter umzieht.

Erster Bewohner ist `COLOR`, und der Grund dafür ist kein Platzmangel, sondern
der Befund vom 24.08.2026.

**Der Befund.** Mit `COLOR` in `SDCODE` kam die Maschine mit Zeichenschrott
hoch: die richtigen Zeichencodes durch die falschen Glyphen, dauerhaft, und ein
gelöschter Bildschirm 960 Kopien dessen, was auf Pattern-Index `$20` lag.
Dasselbe ROM ohne `COLOR` läuft einwandfrei. Das Image auf dem Chip war Byte
für Byte das gebaute, der Zeichensatz im ROM unverändert.

**Was ausgeschlossen ist.** Zwei Runden Raten haben zwei neue Fehler erzeugt
und keinen alten behoben. Erst die Messung hat etwas gebracht, und weil der
Bildschirm selbst das defekte Bauteil ist, ging sie auf das LCD: `rom/vdp_diag`
fährt den Kaltstart Schritt für Schritt, druckt danach Text über genau die
Routinen, die BASIC benutzt, und meldet nach jedem Abschnitt, ob die
Pattern-Tabelle im VRAM noch zum ROM passt.

```
PRB 5A A5  ST E2      VRAM nimmt und gibt zurueck, Chip liefert Bilder
M1 FFFF ENB FFFF      Kaltkopie fehlerfrei, auch nach Display-Ein
TXT FFFF  SH 0000     20 Zeilen Text: Zeichensatz unberuehrt
SCR FFFF              40 Zeilen mit Scrollen: unberuehrt
```

Damit sind erledigt: der VDP als Bauteil, die Kaltkopie, die Zugriffszeit des
Steuerports, das Flip-Flop, die Textausgabe und der Scroll-Pfad. Zwei Fixe, die
auf diese Verdachte gebaut waren — Rücklese-Prüfung des Kaltstarts und Taktung
jedes Adresspaares — sind wieder zurückgenommen; sie haben nichts geändert und
die Taktung kostete das Fünffache an Ausgabezeit.

**Was übrig bleibt.** `COLOR` verändert am Image genau zwei Dinge: 25 Bytes in
`SDCODE`, die alles dahinter verschieben, und ein Token mehr, wodurch jedes
Funktions- und Operator-Token um eins hochrückt. Sonst nichts — `RODATA` und
der Zeichensatz sind identisch, der Code von `COLOR` läuft beim Start nie.

Der Umzug nach `EXTCODE2` trennt die beiden. Gegen das ROM, das nachweislich
läuft, unterscheidet sich der Stand jetzt in:

```
CODE            34  nur Immediates, Länge unverändert
BAS_VEC/KEY/ERR 341 die Tokentabelle mit COLOR
EXTCODE2        25  COLOR, in vorher leerem ROM
SDCODE           0  nichts verschoben
alles andere     0
```

**Es läuft.** Damit ist es die Verschiebung und nicht die Tokentabelle — siehe
Abschnitt 5.2.3.

**Arbeitsregel, die daraus folgt:** neue Statements und neue Routinen kommen
nach `EXTCODE2`. Der Block liegt hinter allem, was sonst im Image steht, also
verschiebt eine Ergänzung dort nichts. `SDCODE` und `EXTCODE` sind ab jetzt
gesperrt für Einschübe; wer dort etwas ändern muss, hält die Länge des Moduls
konstant.

### 5.2 Warum `SDCODE` ein eigener Block ist

> **Gelöst am 29.08.2026 — siehe 5.5.** Alles, was in 5.2 bis 5.2.3 über
> gefährliche Verschiebungen steht, war die Beobachtung eines Hardwarefehlers:
> der Adressdekoder erzeugte bei jedem Schreibzugriff auf den VDP einen
> Stör-Lesezugriff, und ob er entstand, hing daran, welche Adresse als Nächstes
> geholt wurde. Ein Gatter am '138 hat das beseitigt. Die Abschnitte bleiben als
> Protokoll stehen, ihre Regeln gelten nicht mehr.

`SDCODE` ist mit `offset=$4c00` fest positioniert und liegt damit *hinter* allem anderen,
statt wie üblich am Ende von `CODE`. Der Grund ist kein Platzproblem, sondern ein Befund
aus der Hardware-Fehlersuche vom 10.08.2026:

Solange `db6502_sdbasic.s` in `CODE` lag, wuchs `msbasic.o` um ca. 1,1 KB und schob damit
**jedes Bibliotheksmodul dahinter auf neue Adressen** — `CODE` endete auf `$E08D` statt
`$DC37`, `RODATA_PA` rutschte von `$E500` auf `$EA00`. Auf dieser Platine bleibt der
VDP-Bildschirm dann blau ohne Textausgabe.

Das ist **kein Softwarefehler**. Nachgewiesen mit zwei Kontroll-ROMs:

* Ein ROM aus *unveränderten* Quellen plus 1110 toten Füllbytes in `CODE` — also mit
  identischem Verhalten, nur verschoben — zeigt denselben Defekt.
* Ein 65C02-Simulationslauf beider ROMs vom Reset-Vektor an liefert identische
  VDP-Transaktionen: 122 Kontrollport-Schreibzugriffe, `R1 = $D0` (Display an),
  `R7 = $F4`, Banner korrekt in der Namenstabelle.

Ebenfalls ausgeschlossen: der VDP-Treiber (Code und Registertabelle sind byteidentisch,
nur reloziert), die RAM-Aufteilung (ein ROM mit Baseline-Code und der neuen RAM-Karte
läuft), und das Timing (1 MHz, `clock_mode_flag=2`).

Die Ursache liegt damit außerhalb der Software — verdächtig sind das EEPROM oder die
Adressdekodierung. **Konsequenz für künftige Änderungen:** neuen Code bevorzugt in
`SDCODE`, `EXTCODE` oder einen weiteren fest positionierten Block legen.

### 5.2.1 Nachtrag 2026-08-16: es ist nicht das Wachsen, es ist das Verschieben

Die ursprüngliche Formulierung — "wächst `CODE` über etwa `$DC50` hinaus" — legte eine
Größenschwelle nahe. Die gibt es nicht. Beim Entfernen des `jsr _sd_init` aus
`_system_init` **schrumpfte** `CODE` um drei Bytes, blieb also weit unterhalb jeder
Schwelle: Bildschirm schwarz. Reproduziert, zweimal geflasht.

Drei Bytes weniger in `core.o` verschieben jedes Bibliotheksmodul dahinter. Byteweise
gegen das laufende ROM waren das 7281 abweichende Bytes in `CODE`, 1493 in `RODATA`,
389 in `BAS_*`, 68 in `SYSCALLS` und eines in `VECTORS` — praktisch jeder absolute
Operand, der hinter `core.o` zeigt. `RODATA_PA` blieb durch das Page-Alignment liegen,
half aber nichts.

Kontrollen am selben Tag, beide laufen: das unveränderte ROM aus `HEAD`, und eine
Fassung derselben Änderung, bei der `CODE`, `RODATA`, `BAS_*`, `RODATA_PA`, `SYSCALLS`
und `VECTORS` byteidentisch bleiben (5 abweichende Bytes in `CODE`, alle übrigen
Segmente 0). Damit ist die Relokation als Auslöser bestätigt und ein misslungener
EEPROM-Brand als Erklärung ausgeschlossen.

**Arbeitsregel.** Code, der in ein bestehendes Modul muss, darf dessen Länge nicht
ändern:

* Wegfallende Aufrufe durch `nop` ersetzen statt streichen — so gehandhabt in
  `core.s`, wo der SD-Init beim Booten entfiel.
* Neue Routinen ans **Ende** von `EXTCODE` oder `SDCODE` hängen und über eine
  gleich breite Call-Site erreichen. `JMP COLD_START` → `JMP sd_coldstart` und
  `jsr sd_panelprompt` → `jsr sd_promptled` in `db6502_sdbasic.s` sind die Muster:
  nur der Operand ändert sich, kein Byte wandert.
* Vor dem Flashen gegen das zuletzt auf der Hardware bestätigte ROM byteweise
  vergleichen. `CODE`, `RODATA`, `BAS_*`, `RODATA_PA`, `SYSCALLS` und `VECTORS`
  dürfen nur in Operanden abweichen. `make romcheck` tut genau das und prüft
  gegen `rom/<projekt>/reference.ext.bin`; `make romfreeze` setzt die Referenz
  neu, und zwar erst, nachdem das Image auf der Platine lief.

### 5.2.2 Nachtrag 2026-08-21: verschobener Code läuft

Der `SOUND`-Befehl war das erste Image seit dem VDP-Fix, bei dem tatsächlich Code
an neue Adressen gewandert ist: der `sd.o`-Anteil am Ende von `EXTCODE` um 76 Bytes,
dazu `BAS_KEY` und `BAS_ERR`. Auf der Platine geflasht und getestet — **Bild kommt,
`SOUND` spielt, `LOAD` und `SAVE` funktionieren weiter.**

Damit ist die Regel in ihrer absoluten Form widerlegt. Verschieben allein tötet den
Bildschirm nicht.

**Warum die alte Diagnose trotzdem so aussah.** Sämtliche Belege für 5.2 und 5.2.1
stammen vom 10. und 16.08. Der VDP-Kaltstart war zu diesem Zeitpunkt unabhängig
davon kaputt: das Flipflop am Kontrollport wurde nie gelöscht und die Zugriffe lagen
unter den ~8 µs, die der TMS9918A braucht. Das Fehlerbild war entsprechend
sprunghaft — Zeichensalat, nichts, oder der korrekte Schirm aus demselben Image,
und ein ROM, das ohne jede Änderung von schwarz auf laufend umsprang. Bei einem
sporadischen Fehler liefert eine Handvoll Brenn-und-Schau-Durchgänge mühelos ein
überzeugendes, aber falsches Muster. Der Fix kam am 19.08. (`3e44b4c`), drei Tage
nach der Schlussfolgerung — die beiden wurden nie gegeneinander geprüft.

**Was damit noch nicht geprüft ist.** Dieser Test hat `CODE` nicht angefasst:
Segment gleich lang, gleiche Adresse, nur 34 geänderte Immediates. Der Ausfall vom
16.08. entstand dagegen dadurch, dass `CODE` schrumpfte und **jedes Bibliotheksmodul
darin** weiterrückte. Das ist die deutlich größere Verschiebung, und sie steht
weiterhin aus. Wer es wissen will: ein ROM aus unveränderten Quellen plus ein paar
hundert toten Füllbytes am Anfang von `CODE`, brennen, hinsehen.

**Konsequenz für die Arbeitsregel oben.** Sie bleibt als Vorsichtsmaßnahme sinnvoll,
aber nicht mehr als Naturgesetz: Byte-Stabilität ist billig zu haben und `romcheck`
macht Abweichungen sichtbar, also lohnt sie weiter. Ein Feature deswegen zu
verkleinern oder wegzulassen ist dagegen nicht mehr begründet.

**Platz, Stand 2026-08-21.** Beide Offset-Blöcke sind praktisch voll: `EXTCODE`
hat noch 24 freie Bytes, `SDCODE` noch 12 bis `SYSCALLS` bei `$F800`. `SOUND`
(76 Bytes, `EXTCODE`), `CLS` (37) und `COLOR` (25, beide `SDCODE` — in
`EXTCODE` war kein Platz mehr) waren die letzten Erweiterungen, die ohne neuen
Block unterzubringen waren. `SDCODE` hat seitdem nur noch 5 freie Bytes.

**Nachtrag 2026-08-24.** Der neue Block ist da: `EXTCODE2` auf `$F900`, siehe
Abschnitt 5.1.1. Genau wie vorgeschlagen mit einer kleinen, gut sichtbaren
Funktion angefangen. Damit ist der Bereich `$F8A2`–`$FFF9` nicht länger
unerprobt, und es sind noch 1603 Bytes frei.

**Was `SOUND` am Image verändert hat.** Ein neues Statement lässt sich nicht
adressneutral einbauen, aber der Schaden bleibt eng begrenzt. Das Keyword wächst
`BAS_KEY` um 5 Bytes, der Sprungvektor `BAS_VEC` um 2; `BAS_ERR` rückt dadurch
nach, bleibt aber innerhalb des Vorlaufs vor dem Page-Alignment von `RODATA_PA`.
Damit stehen `RODATA_PA`, `SDCODE`, `SYSCALLS` und `VECTORS` unverändert, und
`CODE` behält seine Länge — dort ändern sich nur 34 Bytes, die Immediates der
Funktions-Tokens, die hinter dem neuen Statement um eins hochrücken. Bewegt hat
sich einzig der `sd.o`-Anteil am Ende von `EXTCODE`, um die 76 Bytes der neuen
Routine. Der `romcheck`-Lauf dazu:

```
CODE       $A003-$DC0B    34  operands only
EXTCODE    $E700-$EBE7   326  resized +76 (pinned)
BAS_VEC    $E308-$E38F    67  RESIZED +2
BAS_KEY    $E38E -> $E390       MOVED
BAS_ERR    $E474 -> $E47B       MOVED
RODATA_PA / SDCODE / SYSCALLS / VECTORS   identisch bzw. nur Operanden
```

Das ist auch der Grund, warum der allozierende Schreibpfad (Datei anlegen, Cluster
vergeben) am Ende von `libfat32.s` in einem eigenen `.segment "SDCODE"` steht und
`fat32_init` unangetastet blieb: die dort fehlenden BPB-Felder holt `fat32_readbpb` bei
Bedarf neu von der Karte, statt sie beim Booten zu merken. Verifiziert per Byte-Vergleich
gegen das auf der Hardware bestätigte ROM — `CODE`, `RODATA`, `BAS_*`, `RODATA_PA`,
`SYSCALLS` und `VECTORS` sind unverändert; abweichend sind allein sechs Operandenbytes,
nämlich die vier Sprungziele der Hooks (`sd_getline`, `sd_newline`, `sd_putbyte`,
`sd_finish`) — dazu ein Byte in `BAS_VEC` (`$E395`, Low-Byte der `SAVE`-Adresse in der
Anweisungstabelle). Alle sieben wandern zwangsläufig mit, weil `SDCODE` selbst gewachsen ist.

Genau so ist `EXTCODE` bei `offset=$4700` entstanden: ein **zusätzlicher** Block in der
bis dahin ungenutzten Lücke, nicht ein verschobenes `SDCODE`. Er nimmt das LCD-Panel, die Laufwerks-LED,
die Fehlertexte, die FSInfo-Buchführung und die `BLOCKS FREE`-Zeile auf; das Auslagern der Texte hat `SDCODE` gleich
wieder auf 305 freie Bytes gebracht. In `EXTCODE` sind noch 118 frei.

Der Bereich `$E700`–`$EBFF` war auf dieser Platine zuvor **nie belegt** — er lag im
`$EA`-Füllbereich. Ob er sich anders verhält als der Rest, ließ sich nur durch Benutzen
herausfinden; deshalb kam er bewusst zuerst mit einer kleinen, gut sichtbaren Funktion an
die Reihe. Auf der Hardware bestätigt am 10.08.2026: Bild bleibt, Statuszeile erscheint.

---

### 5.2.3 Nachtrag 2026-08-25: es ist doch die Verschiebung — und sie ist adressabhängig

Der `COLOR`-Befehl hat die Regel wieder aufgerichtet, diesmal mit der saubersten
Kontrolle, die es bisher dazu gab.

**Der Versuch.** Ein ROM mit `COLOR` in `SDCODE` zeigt Zeichenschrott. Dasselbe
ROM mit `COLOR` in `EXTCODE2` läuft. Gegen die Fassung, die auf der Platine
bestätigt lief, unterscheiden sich die 25 Bytes in vorher leerem ROM, 34
Immediates in `CODE` bei unveränderter Länge und die Tokentabelle. `SDCODE`,
`EXTCODE`, `RODATA`, `RODATA_PA`, `SYSCALLS` und `VECTORS`: **null abweichende
Bytes.** Eine Variable, und sie entscheidet.

**Was vorher ausgeschlossen wurde**, damit dieser Schluss trägt — alles auf der
Hardware gemessen, nicht simuliert, mit `rom/vdp_diag` über das LCD, weil der
Bildschirm selbst das defekte Bauteil ist: der VDP als Bauteil, die Kaltkopie
des Zeichensatzes, die Zugriffszeit des Steuerports, das Flip-Flop, die
Textausgabe und der Scroll-Pfad. Alle vier Prüfpunkte `FFFF`, Verschiebung
`0000`, siehe 5.1.1.

**Und der Zusatzbefund, der die Sache erst interessant macht.** Es ist nicht
"jede Verschiebung tötet den Bildschirm":

| Änderung | Verschiebung des `SDCODE`-Rumpfs | Ergebnis |
|---|---|---|
| `SOUND` (2026-08-21) | 0 (nur `EXTCODE`-Ende, 76 Bytes) | läuft |
| `CLS` | +37 | läuft |
| `CLS` + `COLOR` | +62 | Zeichenschrott |
| `CLS`, `COLOR` in `EXTCODE2` | +37 | läuft |

+37 ist harmlos, +62 nicht. Der Effekt ist also **adressabhängig, nicht
größenabhängig** — irgendetwas landet bei +62 auf einer Adresse, die es bei +37
nicht tut. Damit sind auch 5.2.2 und dieser Abschnitt kein Widerspruch: der
`SOUND`-Umzug betraf `EXTCODE`, nicht den Rumpf von `SDCODE`.

**Die Ursache ist weiterhin unbekannt.** Was feststeht, ist eine reproduzierbare
empirische Regel, keine Erklärung. Wer sie knacken will, hat jetzt einen
billigen Aufhänger: dasselbe ROM mit Füllbytes am **Anfang** von `SDCODE`, in
Schritten zwischen +37 und +62, und schauen, wo genau es kippt. Die Schwelle
verrät die Adresse, und die Adresse verrät den Mechanismus.

### 5.3 Die Schlüsselworttabelle und ihre aufgehobene Grenze

`BAS_KEY` war bis 25.08.2026 auf 256 Bytes begrenzt, und das war das knappste
Budget für neue Befehle — nicht der Platz im ROM. `program.s` lief die Tabelle
an sieben Stellen mit einem **8-Bit-Y** ab. Jedes Byte musste damit mit einem
Indexregister von `TOKEN_NAME_TABLE` aus erreichbar sein, **die abschließende
Null eingeschlossen**.

Bei 257 Bytes liegt diese Null auf Offset 256. Y läuft auf null über, der Scan
beginnt wieder beim ersten Schlüsselwort und findet nie ein Ende: die Maschine
hängt beim **ersten ENTER**, weil das der erste Moment ist, in dem überhaupt
etwas tokenisiert wird. Bis dahin läuft alles, inklusive Startbild, LCD-Panel
und Grafikbefehlen — das Fehlerbild sieht nach allem Möglichen aus, nur nicht
nach einer Tabelle, die ein Byte zu lang ist. Genau das ist mit `LINE` passiert.

#### Wie die Grenze aufgehoben wurde

Y bleibt der Index, dazu kommt eine Seite. `keyptr` in der Zero Page zeigt auf
den Anfang der 256-Byte-Seite, in der Y gerade steht, und wird weitergezogen,
sobald Y überläuft. Das braucht keine Mitarbeit des Aufrufers: Y bewegt sich
immer nur um eins und immer nur vorwärts, also **kann ein niedrigerer Index als
beim letzten Aufruf nur bedeuten, dass er gerade umgelaufen ist.**

Der Startwert ist der Kniff, der es einheitlich macht. Beide Aufrufer beginnen
mit Y auf `$FF` und gehen vor dem ersten Lesen auf null — nach obiger Regel ein
Überlauf. Also startet der Zeiger eine Seite *unter* der Tabelle, und genau
dieser erste Überlauf bringt ihn darauf. Kein Sonderfall für den Einstieg.

`keyptrm1` läuft eine Position hinter `keyptr` her, für die eine Stelle, die das
Byte *vor* dem Index liest. Mit `dey`/`iny` zu rechnen läse in genau dem Fall
aus der falschen Seite, um den es hier geht: dem Schritt, in dem Y gerade
umgelaufen ist und das gesuchte Byte das letzte der Seite davor.

#### Warum das `CODE` nicht anfassen durfte

Alle sieben Lesestellen waren drei Bytes absolut-indiziert, ein `jsr` ist auch
drei — `CODE` behält damit Adresse **und** Länge, was auf dieser Platine keine
Kosmetik ist (5.2.3). Zwei Stellen mussten sich das dritte Byte allerdings beim
Nachbarn holen, weil ein Speichern in die Zero Page nur zwei Bytes braucht:

* Tokenizer: `sty EOLPNTR` + `dey` → `jsr key_init`, das beides erledigt
* `LIST`: `tax` + `sty FORPNT` → `jsr key_init_list`, das folgende `ldy #$FF`
  bleibt stehen und stört nicht

Die Routinen liegen in `EXTCODE2`, **hinten angehängt**, damit `COLOR`,
`SCREEN`, `PLOT`, `LINE` und die Startauswahl ihre Adressen behalten. Beim
ersten Versuch standen sie vorn und haben vier Bytes in `BAS_VEC` bewegt.

`romcheck` danach: `CODE` identisch in Adresse und Länge mit 79 geänderten
Operanden, `RODATA`, `RODATA_PA`, `EXTCODE`, `SDCODE`, `SYSCALLS` und `VECTORS`
byteidentisch, `EXTCODE2` um 80 Bytes gewachsen in vorher leeres ROM.

#### Der Beweis

Die Seitenlogik wurde vorab simuliert — 200 Läufe über je 700 Indizes, mit dem
realen Aufrufmuster inklusive Mehrfachaufrufen bei unverändertem Y, alle
effektiven Offsets lückenlos und monoton.

Auf der Hardware zeigt sie sich aber nur, wenn die Tabelle 256 Bytes
überschreitet. Deshalb ist `NULL` wieder in der Tabelle: es kostet nichts, es
war nur wegen dieser Grenze geflogen, und es bringt sie auf **genau 257 Bytes**
— die Größe, bei der die Maschine vorher beim ersten ENTER stehenblieb. Ein
Startvorgang mit angenommener Eingabe ist damit der Test; auf der Platine
bestätigt am 25.08.2026, inklusive `LIST`, `LOAD "$"` und einem geladenen und
gestarteten Programm. `CIRCLE` hat die Tabelle danach auf 263 Bytes gebracht.

Kosten: rund 25 Zyklen je gelesenem Tabellenbyte, also einige zehn Millisekunden
für eine ganze Eingabezeile, einmal beim Drücken von ENTER.

### 5.4 XMODEM aus dem BASIC-ROM, und der Test, der damit endlich ansteht

`modem.o` steckte im BASIC-ROM, obwohl MS-BASIC keine Datei über die serielle
Schnittstelle überträgt — `LOAD` und `SAVE` gehen auf die Karte. Hereingezogen
hat es die Syscall-Tabelle: `syscalls.s` nennt `_modem_send` und
`_modem_receive`, und das ist `ld65` Referenz genug, das ganze Modul aus der
Bibliothek zu holen.

| Segment | Bytes | |
|---|---|---|
| `CODE` | 345 | |
| `RODATA` | 118 | |
| `RODATA_PA` | 512 | XMODEM-CRC-Tabellen, page-aligned |
| `BSS` | 140 | RAM |
| `ZEROPAGE` | 7 | RAM |

Die 512 waren die teuren. Sie sind der Grund, warum `RODATA_PA` auf `$E500` lag
und die Schlüsselworttabellen in die 39 Bytes Vorlauf davor eingesperrt waren.
Ohne sie reicht der freie Bereich von `$E30A` bis `EXTCODE` auf `$E700` —
**1014 Bytes**, in die `BAS_VEC`, `BAS_KEY` und `BAS_ERR` wachsen können. Die
Befehlsdecke ist damit weg.

**Wie es rausfliegt, ohne die Bibliothek anzufassen.** `db6502_extra.s`
definiert `_modem_send` und `_modem_receive` selbst, als `sec` / `rts`. `ld65`
löst sie gegen dieses Objekt auf, das auf der Kommandozeile steht, und sucht
gar nicht erst in der Bibliothek. Die Syscall-Tabelle behält ihr genaues Layout
und jeder andere Eintrag seine Adresse — dieselbe Konstruktion wie bei
`gtx_stub.s`, nur andersherum. `rom/modem_test` und `rom/minimal_bootloader`
definieren nichts dergleichen und linken das echte Modul unverändert.

**Und das ist zugleich der Test, der seit 5.2.1 aussteht.** `modem.o` stand an
neunter von zwanzig Stellen der `CODE`-Reihenfolge; es zu entfernen verschiebt
elf Bibliotheksmodule — `string`, `utils`, `via_utils`, `vdp`, `vdp_text_mode`,
`sound`, `tty`, `parse`, `menu`, `sd` — dazu `RODATA` und `BAS_*`.

```
CODE      $A003-$DC0B -> $A003-$DAB2   6155 Bytes anders, RESIZED -345
RODATA    $DC0C-$E307 -> $DAB3-$E138   MOVED
BAS_*     MOVED
EXTCODE / SDCODE / SYSCALLS / VECTORS  auf ihren festen Offsets
```

Das ist genau die Änderungsklasse vom 16.08.2026, die damals den Bildschirm
schwarz ließ und die seit dem VDP-Fix nie sauber wiederholt wurde. 5.2.3 hält
sie als offene Frage fest. Läuft dieses Image, ist die Frage beantwortet und
die Regel gilt nur noch für `SDCODE`; läuft es nicht, ist sie bestätigt und
gilt für `CODE` genauso.

### 5.5 Aufgelöst: eine Mikrosekunde — und ein Gatter

Der Versuch aus 5.4 ist durch, und er hat **zwei** Antworten geliefert.

**Erstens: `CODE`-Relokation ist überlebbar.** Elf Bibliotheksmodule auf neue
Adressen, `CODE` 345 Bytes kürzer, `RODATA` und `BAS_*` verschoben, 6158
abweichende Bytes — die Maschine läuft. Die offene Frage aus 5.2.1 ist damit
beantwortet, und zwar mit *nein*.

**Zweitens, und das ist das eigentliche Ergebnis:** die Verschiebung hat
trotzdem etwas kaputtgemacht, und das Fehlerbild war diesmal fein genug, um die
Ursache zu zeigen. Nicht schwarzer Schirm, nicht zerstörter Zeichensatz,
sondern **einzelne Zeichen, die fehlen oder um ein paar Spalten versetzt
sitzen**, bei ansonsten korrekter Zeile und richtig stehendem Prompt.

Das ist kein Adressierungsfehler. Das ist ein verlorener Buszugriff.

```asm
      sta VDP_REG                ; Zugriff im 4. Zyklus
      lda vdp_vram_address+1     ; 3
      ora #VDP_WRITE_VRAM_SELECT ; 2
      sta VDP_REG                ; Zugriff im 4. Zyklus
```

Neun Zyklen zwischen den beiden Zugriffen bei 1 MHz. Der TMS9918A verlangt
acht. **Eine Mikrosekunde Marge** — in `load_vram_char_position`, also auf dem
heißesten Pfad der Maschine, und für jedes einzelne ausgegebene Zeichen neu.
Über `vdp_write_address` getaktet sind es sechzehn, und das Bild steht.

#### Was das für 5.2, 5.2.1 und 5.2.3 bedeutet

Es gibt jetzt einen **Mechanismus**, und er erklärt die ganze Familie von
Symptomen aus einer Wurzel:

* Geht die zweite Hälfte eines Adresspaares verloren, bleibt das Flipflop am
  Steuerport mitten im Paar stehen. Ab da wird jedes Paar versetzt gelesen, die
  Zieladresse springt irgendwohin im VRAM — **auch in die Pattern-Tabelle**.
  Zeichen, die auf den Schirm sollten, überschreiben den Zeichensatz. Das ist
  „Zeichenschrott" aus 5.1.1, exakt.
* Geht ein Datenschreibzugriff verloren, fehlt ein Zeichen und der Rest der
  Zeile stimmt weiter. Das ist das Bild von heute.
* Bleibt das Display-Enable-Register auf der Strecke, ist der Schirm schwarz.
  Das ist 5.2.

Relokation war demnach nie die Ursache, sondern die **Störung**: sie verschiebt
Code über Seitengrenzen, ändert Sprungziele und damit einzelne Zyklen — und bei
einer Marge von einer Mikrosekunde entscheidet das, welche der grenzwertigen
Zugriffe diesmal durchfallen. Deshalb sah es adressabhängig aus, deshalb war es
nicht größenabhängig, und deshalb ließ es sich nie auf eine Schwelle festnageln.

#### Was die Mikrosekunde nicht erklärt

Der Verdacht lag nahe, dass auch der `SDCODE`-Befund aus 5.2.3 nur ein Gesicht
derselben Sache ist: ein verschobenes Flipflop legt Zeichen in die
Pattern-Tabelle, und das *ist* ein zerstörter Zeichensatz. Nachgemessen am
25.08.2026, und die Antwort ist **nein**.

`COLOR` zurück nach `SDCODE`, mit jedem VDP-Zugriff getaktet — `CODE` und
`RODATA` byteidentisch, `SDCODE` endet wieder auf `$F7F3`, also exakt auf der
Adresse des Images, das damals ausfiel. Ergebnis: **derselbe Fehler, derselbe
erste Start.** Zeichensatz zerstört, `CLS` füllt den Schirm mit einem falschen
Glyph, `SCREEN 0` holt ihn nicht zurück. `COLOR` selbst funktionierte, wie
immer, weil `vdp_write_register` seine Wartezeit schon hatte.

Das Makro kann es nicht gewesen sein: `vdp_set_vram_addr` wird nur von
`vdp_clear_screen` erreicht, also von `CLS`, und der Schrott stand schon beim
Einschalten da.

**Also zwei verschiedene Fehler, nicht einer.**

* Die Mikrosekunde ist echt und behoben. Sie erklärt fehlende und versetzte
  Einzelzeichen, und das Image ohne XMODEM läuft seitdem.
* Der `SDCODE`-Einschub ist echt, unabhängig davon, und **zum zweiten Mal
  überführt** — beim zweiten Mal mit einem Codestand, der sich vom ersten in
  fast allem unterscheidet. Der Mechanismus bleibt unbekannt.

Damit steht auch fest: `CODE`-Relokation ist harmlos (5.4), `SDCODE`-Einschub
nicht. Es ist also keine Frage der Verschiebung an sich, sondern etwas an
*diesem einen Block*. Der nächste Versuch hätte einen sehr engen Korridor:
dieselben 25 Bytes einmal am Anfang von `SDCODE` und einmal als Füller am
**Ende**. Bleibt der Rumpf dabei liegen und es läuft, liegt es am Verschieben
des Rumpfes; läuft es auch dann nicht, liegt es an der Länge des Blocks.

**Arbeitsregel, unverändert:** neue Statements nach `EXTCODE2`. `SDCODE` und
`EXTCODE` sind für Einschübe gesperrt.

#### Was der Fehler ist: der Rumpf von `SDCODE` an anderen Adressen

`COLOR` vorn in `SDCODE` tat zwei Dinge auf einmal — der Rumpf rückte 25 Bytes
hoch, und der Block wurde 25 Bytes länger. Am 25.08.2026 auseinandergenommen.

**Die Länge scheidet ohne Brennvorgang aus.** Dieselben 25 Bytes als toter
Füller ans *Ende* des Blocks ergeben ein ROM, das byteweise das laufende ist:
das Füllbyte für unbelegtes ROM ist `$EA`, und `$EA` ist `nop`. Der Chip kann
die beiden Images nicht unterscheiden.

**Der Rumpf ist es.** 25 tote Bytes vor allem anderen in `SDCODE` — kein
Statement, kein Schlüsselwort, kein verschobenes Token, `CODE`, `RODATA`,
`BAS_KEY`, `BAS_ERR`, `SYSCALLS` und `VECTORS` unbewegt, nur `SDCODE` um 25
Bytes weitergerückt. Gebrannt, kalt gestartet: **Zeichenschrott.**

Damit ist die Regel keine Faustregel mehr, sondern ein Messergebnis:

* Es ist **nicht** der Inhalt. Tote `nop`s tun es genauso wie ein Statement.
* Es ist **nicht** die Länge des Blocks.
* Es ist **nicht** Relokation an sich — `modem.o` zu entfernen verschiebt elf
  Bibliotheksmodule und kürzt `CODE` um 345 Bytes, und das läuft (5.4).
* Es ist der **Rumpf von `SDCODE` auf anderen Adressen.** Sonst nichts.

**Was daran auffällt.** In `SDCODE` liegen unter anderem die getakteten
VDP-Primitive selbst — `vdp_wait`, `vdp_write_address`, `vdp_write_register` —
und der komplette Kaltstart `vdp_boot_*`. Eine Verschiebung bewegt also genau
die Routinen, die den Bildschirm aufsetzen. Ihre Laufzeit ist zwar
adressunabhängig (`jsr`/`rts` kosten überall gleich, Sprünge über Seitengrenzen
gibt es in ihnen nicht), aber der Verdacht liegt näher an ihnen als an
`libfat32`.

**Nächster Schritt, falls jemand weitergräbt:** die Bewohner von `SDCODE`
einzeln bewegen statt alle zusammen — einmal so, dass nur die VDP-Routinen
wandern, einmal so, dass nur `libfat32` wandert. Das halbiert den Verdächtigen
bei jedem Brand. Der erste dieser beiden Schnitte steht als Nächstes.

#### Der Schnitt: nur die VDP-Routinen wandern

`SDCODE` hat vier Bewohner, in Linkreihenfolge:

| Offset im Block | Bytes | Modul | Inhalt |
|---|---|---|---|
| `$000` | 1117 | `msbasic.o` | Rumpf von `db6502_sdbasic.s`, `CLS` |
| `$45D` | 131 | `vdp.o` | `vdp_wait`, `vdp_write_address`, `vdp_write_register`, `vdp_boot_registers/patterns/clear/enable` |
| `$4E0` | 100 | `vdp_text_mode.o` | `vdp_boot_init`, `vdp_alive` |
| `$544` | 1687 | `sd.o` | allozierender Schreibpfad aus `libfat32.s` |

Füllbytes irgendwo dazwischen verschieben immer *alles dahinter*. Um genau einen
Bewohner zu bewegen, muss sein Platz nachbesetzt werden: die 231 Bytes der
beiden VDP-Anteile ziehen in den freien Schwanz von `EXTCODE2`, und an ihrer
Stelle in `SDCODE` bleiben 231 Bytes `.res` stehen. Ergebnis laut Linker:

* `msbasic.o` liegt weiter bei `$EC00`, `sd.o` weiter bei `$F144` — beide auf
  das Byte an ihrer alten Adresse.
* `SDCODE` behält Anfang, Ende und Länge: `$EC00`–`$F7DA`, 3035 Bytes.
* `CODE`, `RODATA`, `BAS_*`, `EXTCODE`, `SYSCALLS` und `VECTORS` sind identisch,
  bis auf 6 `jsr`-Operanden in `CODE`, die auf die neue Adresse zeigen.
* `EXTCODE2` wächst um dieselben 231 Bytes, sein bisheriger Inhalt bleibt an
  Ort und Stelle (33 Operanden zeigen woanders hin).

Damit bewegte dieser Brand als einziges die Routinen, die den Bildschirm
aufsetzen. Gebrannt, kalt gestartet: **Zeichenschrott, und manchmal überhaupt
kein Bild.**

Das ist mehr, als die bisherigen Fehlbilder gezeigt haben. Kein Bild heißt, dass
`vdp_boot_init` seine zwanzig Versuche leer durchläuft: `vdp_alive` schreibt
zwei Bytes nach `$3FFE`, liest sie zurück und prüft das Rahmen-Flag im
Statusregister, und wenn das zwanzigmal nacheinander scheitert, gibt die Routine
absichtlich auf und lässt den Schirm dunkel. Der Chip antwortet in diesen Fällen
also gar nicht mehr, statt nur falsch zu zeichnen.

**Die 231 Bytes VDP-Code allein genügen für den Fehler.** Nicht die 3035 Bytes
des ganzen Blocks, nicht `libfat32`, nicht der SD-Rumpf von BASIC.

#### Die Gegenprobe: nur `libfat32` wandert

Ein Verdächtiger, der beim Verschieben kaputtgeht, ist erst dann einer, wenn die
anderen es beim Verschieben nicht tun. Der Spiegelversuch ist billiger als der
erste, weil `SDCODE` hinten 37 freie Bytes hat und deshalb wachsen darf:

25 Bytes Füller kommen zwischen `vdp_text_mode.o` und `sd.o` zu liegen. `ld65`
ordnet ein Segment in Modulreihenfolge, und `sound.o` ist genau das Modul
dazwischen — deshalb steht der `.res` in `common/source/sound.s` und hat mit
Ton nichts zu tun. Ergebnis:

* `CODE`, `RODATA`, `BAS_*`, `EXTCODE2`, `SYSCALLS`, `VECTORS` — **identisch**.
* `SDCODE` `$EC00`–`$F143` — **identisch**, bis auf vier `jsr`-Operanden, die
  auf `libfat32` zeigen. Der SD-Rumpf von BASIC und **beide VDP-Blöcke stehen
  Byte für Byte auf ihren alten Adressen**, `vdp_wait` weiterhin auf `$F05D`.
* Nur der allozierende Schreibpfad aus `libfat32.s` rückt von `$F144` auf
  `$F15D`, und `EXTCODE` bekommt die vier zugehörigen Operanden.

Gebrannt, kalt gestartet: **sauberes Bild.**

Damit ist es abgeschlossen. `libfat32` darf sich bewegen, die VDP-Routinen
dürfen es nicht, und es sind 231 Bytes, um die es geht:

| Routine | Datei |
|---|---|
| `vdp_wait`, `vdp_write_address`, `vdp_write_register` | `vdp.s` |
| `vdp_boot_registers`, `vdp_boot_patterns`, `vdp_boot_clear`, `vdp_boot_enable` | `vdp.s` |
| `vdp_boot_init`, `vdp_alive` | `vdp_text_mode.s` |

Alles, was den Bildschirm aufsetzt. Nichts sonst.

#### Der Schnitt danach: seitenweise verschieben

Die Frage ist jetzt nicht mehr *welcher* Code, sondern *warum überhaupt*. Zwei
Familien von Erklärungen bleiben übrig, und ein einziger Brand trennt sie:

* **Zeitverhalten.** Ein 6502 zahlt für einen genommenen Sprung über eine
  Seitengrenze einen Takt extra, ebenso für indizierte Zugriffe über eine
  Seitengrenze. Verschiebt man Code um einen beliebigen Betrag, ändert sich, wo
  diese Grenzen fallen — und damit der Abstand zwischen zwei Zugriffen auf den
  Steuerport.
* **Adressen.** Irgendetwas an der Dekodierung oder an der Elektrik reagiert
  darauf, welche Adressleitungen während der Befehlsholung wechseln, während
  der 9918 selektiert ist oder gerade war.

Verschiebt man die Routinen um **ganze Seiten**, bleibt die erste Familie
unberührt: die niederwertigen Adressbytes sind dieselben, jede Verzweigung
kreuzt genau die Seitengrenzen, die sie heute kreuzt, und der Code läuft Takt
für Takt identisch. Nur `A8`–`A15` sind andere.

Deshalb `VDPCODE` auf `$E45D` — dasselbe niederwertige Byte wie das heutige
`$F05D`, exakt zwölf Seiten tiefer, in dem Loch, in dem früher `RODATA_PA` lag.
Der Linker bestätigt die Absicht: von den 231 Bytes des Blocks unterscheiden
sich genau 20, und alle zwanzig sind ein hochwertiges Operandenbyte, das um
`$0C00` kleiner geworden ist. In `CODE` ändern sich 6 Bytes statt 12, in
`EXTCODE2` 33 statt 66 — die niederwertigen Hälften aller `jsr`-Operanden
bleiben, wie sie waren.

Gebrannt, kalt gestartet: **sauberes Bild.**

Damit ist die zweite Familie erledigt. Der 9918 hängt nicht an den Adressen —
er hängt an den Takten. Verschieben ist nur deshalb gefährlich, weil es die
Taktzahl ändert.

#### Welcher Takt

Ein 6502 zahlt einen Takt extra für eine *genommene* Verzweigung über eine
Seitengrenze. Im verschobenen Block stehen elf Verzweigungen, und für jede lässt
sich ausrechnen, ob sie an einer gegebenen Basisadresse eine Seitengrenze
kreuzt. Vier Basisadressen sind gebrannt, zwei liefen und zwei nicht:

| Offset | Befehl | `$F05D` | `$F076` | `$FEB7` | `$E45D` |
|---|---|---|---|---|---|
| | | **gut** | **kaputt** | **kaputt** | **gut** |
| `+$050` | `bne` | — | — | kreuzt | — |
| `+$056` | `bne` | — | — | kreuzt | — |
| `+$09E` | `bcc` | **kreuzt** | — | — | **kreuzt** |
| `+$0A6` | `bne` | kreuzt | kreuzt | — | kreuzt |
| übrige 7 | | — | — | — | — |

Genau eine Zeile passt auf gut/kaputt/kaputt/gut, und es ist `+$09E`. Der Befehl
dort ist `bcc @up` in `vdp_boot_init`, der Sprung, der genommen wird, wenn
`vdp_alive` durchgekommen ist. In beiden laufenden ROMs kreuzt er eine
Seitengrenze und kostet einen Takt mehr, in beiden kaputten tut er das nicht.

Das ist ein Verdacht, keine Messung — elf Verzweigungen, vier Datenpunkte, eine
passende Zeile kann Zufall sein. Also wird er geprüft.

#### Der Test: eine einzige Verzweigung, ein einziger Takt

`VDPCODE` liegt jetzt auf `$E360`. Diese Adresse ist so gewählt, dass von den elf
Verzweigungen **genau eine** ihr Verhalten gegenüber dem laufenden ROM ändert,
nämlich `+$09E`, und alle anderen ihre Taktzahl behalten. Tabellenzugriffe im
Block zeigen auf `RODATA`, das unbewegt ist, also ändert sich auch dort nichts.
Der gesamte Unterschied zum funktionierenden ROM ist **ein Takt auf dem Pfad,
auf dem `vdp_boot_init` den Bildschirm für gut erklärt.**

Gebrannt, kalt gestartet: **sauberes Bild.** Die Korrelation war Zufall.

#### Was damit alles hinfällig ist

Mit fünf Brennvorgängen bleibt von der Verzweigungstheorie nichts übrig. Keine
der elf Verzweigungen hat einen Zustand, der in allen laufenden ROMs gleich und
in allen kaputten anders ist:

| Verzweigung | `$F05D` | `$F076` | `$FEB7` | `$E45D` | `$E360` |
|---|---|---|---|---|---|
| | **gut** | **kaputt** | **kaputt** | **gut** | **gut** |
| `+$050`, `+$056` | — | — | kreuzt | — | — |
| `+$09E` | kreuzt | — | — | kreuzt | — |
| `+$0A6` | kreuzt | kreuzt | — | kreuzt | kreuzt |
| übrige 7 | — | — | — | — | — |

Und mit ihr fällt der Satz, den dieser Abschnitt zwei Brennvorgänge lang
behauptet hat. **„Die VDP-Routinen dürfen sich nicht bewegen" ist widerlegt.**
Sie sind zweimal umgezogen, nach `$E45D` und nach `$E360`, und beide Male lief
das Bild sauber. Was tatsächlich gemessen ist, ist enger:

| Was verschoben wurde | Ergebnis |
|---|---|
| alle vier Bewohner von `SDCODE` um 25 Bytes | kaputt |
| nur die VDP-Routinen, nach `$FEB7` | kaputt |
| nur die VDP-Routinen, nach `$E45D` | gut |
| nur die VDP-Routinen, nach `$E360` | gut |
| nur `libfat32`, um 25 Bytes | gut |

Zwei kaputte Konfigurationen, keine davon erklärt. Was `$FEB7` von `$E360` und
`$E45D` unterscheidet, ist offen; die Taktzahlen sind es nicht.

#### Der letzte ungetestete Bewohner

Der erste Fehlschlag hat vier Bewohner gleichzeitig bewegt. `libfat32` ist
freigesprochen, die VDP-Routinen inzwischen auch — bleibt der Rumpf von
`db6502_sdbasic.s` samt `CLS`, der als einziger noch nie allein umgezogen ist.

25 Bytes Füller ganz vorn in `SDCODE`, und das Loch in `vdp.s` wird um dieselben
25 Bytes kleiner. Damit rückt der BASIC-SD-Rumpf von `$EC00` auf `$EC19`,
`libfat32` bleibt auf `$F144`, die VDP-Routinen bleiben auf `$E360`, und
`SDCODE` behält Anfang, Ende und Länge.

`romcheck.py` meldet dabei zum ersten Mal `REWRITTEN` für `BAS_VEC`, und das ist
in Ordnung: `BAS_VEC` ist die Sprungtabelle der Statements, keine
Befehlsfolge. Die vier geänderten Bytes sind `$EBFF`→`$EC18`, `$4D`→`$66` und
`$37`→`$50` — dreimal derselbe Versatz von 25, einmal mit Seitenübertrag, also
genau die Adressen der mitgewanderten Statements. Das Werkzeug kann eine
Adresstabelle nicht von Code unterscheiden; hier ist es von Hand geprüft.

Gebrannt, viermal kalt gestartet: **sauberes Bild.**

#### Alle Bewohner sind einzeln unbedenklich

| Verschoben | Ergebnis |
|---|---|
| alle vier Bewohner um 25 Bytes | **kaputt** |
| nur die VDP-Routinen, nach `$FEB7` | **kaputt** |
| nur die VDP-Routinen, nach `$E45D` | gut |
| nur die VDP-Routinen, nach `$E360` | gut |
| nur `libfat32`, um 25 Bytes | gut |
| nur der BASIC-SD-Rumpf, um 25 Bytes | gut |

Damit ist die Aufteilung nach Bewohnern zu Ende erzählt, ohne etwas erklärt zu
haben. Kein einzelner Umzug schadet. Zwei Konfigurationen schaden trotzdem.

Was auffällt, wenn man die fünf Adressen des VDP-Blocks nach dem niederwertigen
Byte sortiert — und es ist nicht mehr als eine Auffälligkeit bei fünf Punkten:

| Basis | nied. Byte | Seitengrenze bei Blockoffset | Ergebnis |
|---|---|---|---|
| `$F05D` | `$5D` | `+$0A3` | gut |
| `$E45D` | `$5D` | `+$0A3` | gut |
| `$E360` | `$60` | `+$0A0` | gut |
| `$F076` | `$76` | `+$08A` | **kaputt** |
| `$FEB7` | `$B7` | `+$049` | **kaputt** |

#### Der Brand, der den ersten Fehlschlag erklärt oder umwirft

`$F076` ist die Adresse, die die VDP-Routinen im allerersten Fehlschlag hatten,
und sie sind dort nie allein gewesen. Genau das holt dieser Brand nach: 25 Bytes
Füller ans *Ende* des msbasic-Anteils, also zwischen den BASIC-SD-Rumpf und die
VDP-Routinen. Der SD-Rumpf bleibt damit auf `$EC00` — von 1117 Bytes ändern sich
vier, alle in einem absoluten Operanden —, die VDP-Routinen landen auf `$F076`,
und `libfat32` rückt 25 Bytes hoch, was nachweislich harmlos ist.

Gebrannt, viermal kalt gestartet: **viermal Zeichenschrott.**

Der erste Fehlschlag ist damit erklärt, und zwar durch die Adresse allein. Es
gibt gute und schlechte Adressen für diesen Block:

| Adresse des VDP-Blocks | Ergebnis |
|---|---|
| `$F05D` | gut |
| `$E45D` | gut |
| `$E360` | gut |
| `$F076` | **kaputt** |
| `$FEB7` | **kaputt** |

#### Was das über den Adressdekoder sagt — und was nicht

Die naheliegende Vermutung ist ein falsch aufgebauter Dekoder: irgendein
ROM-Bereich, der nebenbei auch den VDP selektiert, so dass allein das Holen von
Befehlen dort Zugriffe auslöst, die niemand programmiert hat. Das passt zur
Beobachtung — und wird von ihr trotzdem ausgeschlossen. Die laufende Lage
`$F05D`–`$F143` und die kaputte `$F076`–`$F15C` **teilen sich 206 ihrer 231
Bytes**. Dieselben Adressen, entgegengesetztes Ergebnis. Es kann also nicht
sein, dass diese Adressen an sich vergiftet sind; es kommt darauf an, welcher
Befehl auf welcher Adresse liegt.

Was davon übrig bleibt, ist die dynamische Variante, und die ist gut möglich.
Der 6502 legt in dem Takt nach einem Schreibzugriff bereits die Adresse des
nächsten Befehls auf den Bus. Wird die Auswahl für `$8080` allein aus Gattern
gebildet und nicht sauber mit φ2 verriegelt, kann dieser Übergang einen kurzen
Störimpuls auf der Auswahl erzeugen — einen Zugriff, den niemand programmiert
hat. Ob er entsteht, hängt vom Bitmuster der als Nächstes geholten Adresse ab,
also davon, wo der Code liegt. Genau das Verhalten, das gemessen wurde.

Am Aufbau nachzusehen wäre demnach:

1. Ist die Auswahl des VDP mit φ2 (oder einem daraus gebildeten Strobe)
   verriegelt, oder hängt sie nur an Adressleitungen?
2. Wie vollständig ist dekodiert? Eine Teil-Dekodierung über wenige Gatter
   lässt breitere Störfenster zu als eine vollständige.
3. Woraus entstehen `CSR`/`CSW`, und wie breit ist der Impuls?
4. Laufzeit der Dekodierkette gegen die Adress-Vorhaltezeit des 6502.

#### `rom/vdp_alias` — gemessen, und nichts gefunden

Ein Oszilloskop ist dafür nicht nötig: ein Störzugriff verstellt den VRAM-Zeiger,
und das ist sichtbar. Dieselbe 14 Byte lange Probe wurde fünfmal gebunden, auf
die fünf gebrannten Adressen, jede in sich geschlossen — nach dem Schreibzugriff
holte der Prozessor jedes weitere Byte aus der Probe selbst. 256 bekannte Bytes
schreiben, zurücklesen, Abweichungen zählen.

```
PRB 5A A5
F05D 00 F076 00
E360 00 E45D 00
FEB7 00
```

`PRB 5A A5` — der VRAM-Pfad trägt. Und danach fünfmal `00`. **Ein einfacher
Schreibzugriff, ausgeführt von einer der schlechten Adressen, erzeugt keinen
Störzugriff.** Der Versuchs-ROM ist wieder aus dem Baum; das Ergebnis steht
hier, und die Fassung liegt in der Historie.

Was die Probe nicht nachgestellt hat, und was sie beim nächsten Anlauf
nachstellen müsste: sie hat nur den Datenport `$8080` benutzt, nie den
Steuerport `$8081` mit seinem Flipflop, und ihre Pausen waren `nop`s statt
`jsr vdp_wait` — die echten Routinen holen nach jedem Zugriff als Nächstes die
Adresse von `vdp_wait`, und die wandert mit.

#### Ein Buchhaltungsfehler, der zwei Brände kostet

Beim Nachrechnen der Reihe fällt auf, dass `$F076` nie einvariabel war:

| Brand | VDP-Routinen | `libfat32` | Variablen | Ergebnis |
|---|---|---|---|---|
| Referenz | `$F05D` | `$F144` | — | gut |
| `$F076` | `$F076` | `$F15D` | **zwei** | kaputt |
| `$FEB7` | `$FEB7` | `$F144` | eine | kaputt |
| `$E45D` | `$E45D` | `$F144` | eine | gut |
| `$E360` | `$E360` | `$F144` | eine | gut |

Der Füller lag am Ende des msbasic-Anteils, also *vor* den VDP-Routinen — damit
sind auch alle dahinter mitgerückt. Die Aussage „die Adresse entscheidet" ruht
deshalb allein auf `$FEB7` gegen `$E360` und `$E45D`. Das ist ein echter
Einzelvergleich, aber es ist einer und nicht drei.

#### Es ist das niederwertige Byte

`$E3B7` — dasselbe niederwertige Byte wie die durchgefallene Adresse, dieselbe
Gegend wie die bestandenen. Gebrannt, viermal kalt gestartet: **schwarzer
Bildschirm.** Nicht einmal Zeichenschrott; `vdp_boot_init` läuft alle zwanzig
Versuche leer und gibt auf.

| Adresse | nied. Byte | Gegend | Variablen | Ergebnis |
|---|---|---|---|---|
| `$F05D` | `$5D` | `SDCODE` | Referenz | gut |
| `$E45D` | `$5D` | Loch `$E3xx` | eine | gut |
| `$E360` | `$60` | Loch `$E3xx` | eine | gut |
| `$E3B7` | `$B7` | Loch `$E3xx` | eine | **schwarz** |
| `$FEB7` | `$B7` | oberstes ROM | eine | **kaputt** |
| `$F076` | `$76` | `SDCODE` | zwei | kaputt |

Zwei völlig verschiedene Seiten mit demselben niederwertigen Byte fallen beide
durch; drei verschiedene Seiten mit anderen niederwertigen Bytes laufen alle.
Die Gegend ist es nicht. Es ist das niederwertige Byte.

#### Was sich genau so verhält: eine kranke niederwertige Adressleitung

`A0`–`A7` wählen das Byte innerhalb einer Seite. Eine Leitung, die grenzwertig
ist — zu langsam, zu viel Kapazität, eine gerissene Lötstelle — versagt an
denselben Offsets in *jeder* Seite, ganz gleich in welcher. Genau das Muster,
das die Tabelle zeigt.

Und der Rest passt dazu: Code, der an so einem Offset liegt, wird falsch
zurückgelesen. Ein falscher Befehl in der Routine, die den Zeichensatz kopiert,
gibt einen kaputten Zeichensatz; ein falscher Befehl in der Bootschleife gibt
gar kein Bild. Beides ist beobachtet, und die Verzweigungsrechnung wie auch die
Störimpuls-Messung sind erklärtermaßen negativ ausgegangen, weil beide von der
falschen Annahme ausgingen, der Prozessor bekomme überhaupt zu sehen, was
gebrannt wurde.

#### `rom/rom_check` — die Frage direkt gestellt

64 Bytes bekanntes Muster an jeder der fünf Adressen, zur Laufzeit zurückgelesen
und gezählt, wie viele nicht stimmen. Jeder Block trägt eine eigene Kennung
(`$11`, `$33`, `$55`, `$77`, `$99`), damit ein Lesevorgang, der im Nachbarblock
landet, nicht zufällig durchgeht. Dazu die Summe aller 24 KB ROM, die sich mit
derselben Summe über die `.bin`-Datei auf dem Rechner vergleichen lässt.

Erwartet für dieses Image: `SUM 85E4`.

```
SUM 85E4
F05D 00 E360 00
E3B7 00 E45D 00
FEB7 00
```

* **`SUM` stimmt und überall `00`** → das ROM wird korrekt gelesen, die
  Adressleitungen sind in Ordnung, und der Fehler sitzt woanders. Dann bleibt
  als nächstes, den Verdacht vom Lesen aufs Ausführen zu verschieben: dieselben
  Muster nicht lesen, sondern anspringen.
* **`SUM` weicht ab oder ein Block zählt ungleich `00`** → gefunden. Das Brett
  liest nicht, was gebrannt wurde, und die Suche ist eine Frage von
  Durchgangsprüfung und Oszilloskop an `A0`–`A7`, nicht mehr eine von
  Assemblercode.

Zu beachten: ein Lesefehler, der nur unter bestimmten Adressfolgen auftritt,
kann sich bei diesem gemächlichen Prüflauf verstecken. Ein sauberes Ergebnis
schließt eine grenzwertige Leitung also nicht aus, ein schmutziges beweist sie.

Gebrannt: **`SUM 85E4`, und fünfmal `00`.** Die Summe stimmt aufs Byte mit der
über die `.bin`-Datei überein, und jeder der fünf Blöcke kommt vollständig
zurück. Das ROM gibt heraus, was hineingebrannt wurde — jedenfalls beim Lesen.
Damit ist ein hart defektes Bauteil aus, und die Einschränkung des vorigen
Absatzes ist alles, was noch offen ist.

#### `rom/rom_exec` — dasselbe, aber ausgeführt statt gelesen

`rom_check` liest mit `(zp),y` vorwärts, ein Byte alle fünf Takte, in der
einfachsten Adressfolge, die es gibt. Ein laufendes Programm wechselt die
Adresse in jedem Takt und in beliebigen Mustern. Deshalb dieselbe Frage noch
einmal, nur ausgeführt statt gelesen.

Dieselbe 21 Byte lange Routine liegt an den fünf Adressen. Sie benutzt nur
Direktoperanden und eine relative Verzweigung, also sind alle fünf Kopien
byteweise gleich und müssen byteweise gleiche Ergebnisse liefern. 256
Durchläufe einer Rechenkette pro Aufruf, 64 Aufrufe pro Adresse — rund
zweihunderttausend Befehlsholungen je Adresse.

Zwei Zahlen, die verschiedene Fehler fangen:

* **`R`** — Ergebnis des letzten Aufrufs. Alle fünf müssen `$9B` sein. Ein
  abweichender Wert ist eine Adresse, an der immer falsch ausgeführt wird.
* **`I`** — alle 64 Ergebnisse XOR-verknüpft. 64 ist gerade, ein stabiles
  Ergebnis hebt sich also zu `$00` auf, egal welcher Wert. Alles andere heißt:
  die Adresse ist nicht falsch, sondern unzuverlässig.

```
R 9B9B9B9B9B
I 0000000000
```

Reihenfolge `$F05D $E360 $E3B7 $E45D $FEB7`. Gebrannt: **genau das.** Das Brett
holt und führt an all diesen Adressen korrekt aus, auch an den beiden, an denen
die VDP-Routinen durchfallen. Das ROM ist als Ursache erledigt, in beiden
Richtungen. Beide Prüf-ROMs sind wieder aus dem Baum; die Ergebnisse stehen
hier, die Fassungen in der Historie.

#### Was danach übrig ist

Drei Messungen sind negativ ausgegangen, und zusammen schneiden sie den
Suchraum scharf:

| Gemessen | Ergebnis | Damit erledigt |
|---|---|---|
| Seitengrenzen aller elf Verzweigungen über fünf Brände | kein Muster | Taktzahlen im Block |
| Störzugriff durch einen Schreibbefehl von der schlechten Adresse | fünfmal `00` | Adresse des schreibenden Befehls allein |
| Lesen und Ausführen an allen fünf Adressen | `SUM` stimmt, `R`/`I` sauber | das ROM |

Was keine dieser Proben nachgestellt hat, ist die Kombination: ein Zugriff auf
den **Steuerport** `$8081` mit seinem Schreib-Flipflop, gepaart mit
`jsr vdp_wait` als Pause — wobei die als Nächstes geholte Adresse die von
`vdp_wait` ist, und die wandert mit dem Block. Genau dieses Flipflop ist das
Bauteil, dessen Verrutschen seit Monaten als Erklärung für den kaputten
Zeichensatz dasteht (5.5, erster Teil).

#### `vdp_diag` auf `$E3B7` — den echten Code messen statt nachbauen

Zwei nachgebaute Proben sind ins Leere gelaufen. Also nicht mehr nachbauen: der
echte Kaltstart wird an die schlechte Adresse gelegt und dabei vermessen.
`rom/vdp_diag` bringt das schon mit — es geht den Kaltstart Schritt für Schritt
durch und berichtet ans LCD —, und `VDPCODE` auf `$43B7` legt seine
VDP-Routinen auf `$E3B7`, wo sie im BASIC-ROM einen schwarzen Bildschirm
erzeugt haben.

Damit wird aus „das Bild sieht falsch aus" eine Zahl:

* `PRB` ≠ `5A A5` → schon der einfache VRAM-Weg trägt nicht, und das Flipflop
  ist bereits beim ersten Adresspaar verrutscht.
* `M1` ≠ `FFFF` → die Zeichensatzkopie geht ab diesem Byte daneben; `G`/`W`
  sagen, was dort steht und was dorthin gehört.
* `SH` ≠ `0000` → was in VRAM steht, *ist* der Zeichensatz, nur um so viele
  Bytes versetzt — die Signatur eines verrutschten Flipflops.
* `ST` unter `$80` → der Chip gibt keine Bilder aus, und der schwarze Schirm
  ist kein Zeichenfehler, sondern ein toter Chip.
* alles sauber → der echte Code läuft an `$E3B7` in `vdp_diag` fehlerfrei, und
  dann ist es nicht die Adresse für sich, sondern etwas an ihrem Zusammenspiel
  mit dem übrigen BASIC-ROM.

Gebrannt. Der Fehler ist da, und er ist damit aus BASIC heraus in ein 1,2 KB
großes Diagnose-ROM gewandert:

| | gut (Routinen normal) | `$E3B7` |
|---|---|---|
| `PRB` | `5A A5` | **`EF CB`** |
| `ST` | `E2` | `DA` |
| `M1` | `FFFF` | **`0000`** |
| `ENB` | `FFFF` | `0000` |
| `TXT` | `FFFF` | `0140` |
| `SH` | `0000` | **`FFFF`** |
| `SCR` | `FFFF` | `0000` |

Zeile für Zeile gelesen:

* `ST DA` — Bit 7 gesetzt. Der Chip ist getaktet und gibt Bilder aus. Er ist
  nicht tot, der schwarze Schirm ist kein toter Chip.
* `PRB EF CB` — zwei Bytes nach `$3FFE` geschrieben und zurückgelesen, und es
  kommt Müll. Das ist der einfachste Zugriff, den es gibt, und er sitzt vor
  allem anderen. **Schon das erste Adresspaar kommt nicht an.**
* `M1 0000` — folgerichtig ist die Zeichensatzkopie ab ihrem allerersten Byte
  falsch.
* `SH FFFF` — und was in VRAM steht, ist nicht der Zeichensatz an falscher
  Stelle. Es ist gar nicht der Zeichensatz.

Damit ist der Ort benannt: der **Steuerport `$8081` und sein
Schreib-Flipflop**. Genau das Bauteil, das seit Beginn dieses Abschnitts als
Erklärung für zerstörte Zeichensätze dasteht — nur dass es hier nicht
verrutscht, sondern die Adresse überhaupt nicht annimmt.

#### `rom/vdp_lobyte` — den Parameter in einem Brand kartieren

Bisher sind fünf Adressen einzeln gebrannt worden, und jede kostete einen
Brennvorgang für ein Bit Erkenntnis. Das geht besser: dieselbe in sich
geschlossene Probe wird sechzehnmal gebunden, auf die niederwertigen Bytes
`$00` bis `$F0`, jede in einer eigenen Seite (`$B000`, `$B110`, `$B220`, …).
Jede Kopie bringt ihren eigenen Adressschreiber und ihre eigene Pause mit, so
dass jedes Byte, das zwischen zwei Zugriffen auf den Steuerport geholt wird,
das niederwertige Byte dieser Kopie trägt. Die Kopien unterscheiden sich
ausschließlich in den Operanden ihrer eigenen `jsr`/`jmp` — nachgeprüft am
gebauten Image.

Der VDP wird vorher über die gewöhnlichen Routinen hochgefahren, jede Probe
trifft also auf einen laufenden Chip. Sie schreibt `$5A` und `$A5` nach `$3FFE`
und liest zurück; nur wenn beide ankommen, gilt sie als bestanden.

```
00+ 10+ 20+ 30+
40+ 50+ 60+ 70+
80+ 90+ A0+ B0-
C0+ D0+ E0+ F0+
```

* **überall `+`** → das niederwertige Byte allein entscheidet doch nicht, und
  der fehlende Bestandteil ist etwas, das auch diese Probe noch nicht tut.
* **ein Muster von `-`** → die Karte des Fehlers, und ihre Ränder sagen, was er
  ist: ein einzelner Wert ist ein Bit einer Leitung, ein zusammenhängender
  Bereich eine Zeitschwelle, jeder zweite eine einzelne Adressleitung.

Gebrannt:

```
00+ 10+ 20+ 30+
40+ 50- 60+ 70+        $40, $60 und $70 fielen beim ersten Kaltstart mit durch
80- 90- A0- B0-
C0+ D0+ E0+ F0+
```

Nach den obersten zwei Bits des niederwertigen Bytes sortiert ist das ein
sauberer Schnitt:

| `A7` | `A6` | niederw. Bytes | Ergebnis |
|---|---|---|---|
| 0 | 0 | `$00`–`$30` | durchweg gut |
| 0 | 1 | `$40`–`$70` | wackelig, `$50` durchweg schlecht |
| 1 | 0 | `$80`–`$B0` | durchweg schlecht |
| 1 | 1 | `$C0`–`$F0` | durchweg gut |

`A7` und `A6` **gleich** geht immer. `A7` und `A6` **verschieden** fällt durch —
hart, wenn `A7` das gesetzte ist, unzuverlässig, wenn `A6` es ist.

**So sehen zwei gekoppelte Nachbarleitungen aus.** Stimmen sie überein, fließt
zwischen ihnen kein Strom und die Flanke ist sauber; unterscheiden sie sich,
zieht die eine an der anderen. Ein hochohmiger Schluss — Flussmittelrest,
Zinnbrücke, ein Härchen — tut genau das, und er erklärt auch, warum das ROM
sauber blieb: bei einem Lesezugriff übernimmt der 6502 die Daten spät im Takt,
eine träge Adressflanke hat sich bis dahin gesetzt. Das dekodierte
Auswahlsignal des VDP ist der knappe Pfad.

#### Zwei Fehler in dieser Karte, beide meine

**Seite und niederwertiges Byte waren dieselbe Variable.** Probe `k` lag auf
Seite `$B0+k` mit niederwertigem Byte `k*$10`, also war `A11`–`A8` immer gleich
`A7`–`A4`. Der Schnitt kann genauso gut `A11` gegen `A10` sein.

**Die Probe ist 62 Bytes lang.** Eine Kopie „auf `$50`" verbringt ihre Zeit
zwischen `$50` und `$8D` und liegt damit quer über der Grenze. Bei Schrittweite
`$10` ist das die halbe Karte.

#### `rom/vdp_lobyte2` — dieselbe Frage ohne die beiden Fehler

Jedes niederwertige Byte wird zweimal gebunden: Satz A auf Seite `$D0+k`, Satz B
auf Seite `$D0+((k+8) mod 16)`. Gleiche niederwertige Bytes, andere Seiten — am
gebauten Image nachgeprüft. Stimmen die zwei Zeilen überein, entscheidet das
niederwertige Byte und die Seiten sind unschuldig; laufen sie auseinander,
steckt die Seite doch mit drin.

Schrittweite `$08` statt `$10` über das interessante Band `$40`–`$B8`, also
doppelt so fein. Und weil die erste Karte teilweise wackelte, läuft jede Kopie
fünfzehnmal; berichtet wird die Zahl der Fehlschläge als eine Hexziffer.

Gebrannt — und das Ergebnis war, dass es **kein** Ergebnis gibt: die beiden
Zeilen unterscheiden sich, und sie zeigen bei jedem Kaltstart andere Werte.

Das ist selbst der Befund und wichtiger als die Karte. **Der Fehler ist nicht
deterministisch.** Damit misst ein einzelner Durchlauf Rauschen, und der saubere
Schnitt der ersten Karte war zu einem guten Teil Glück — fünfzehn Durchläufe
sind zu wenig, um eine Rate zu schätzen, wenn die Rate irgendwo zwischen null
und eins liegt. Ein sporadischer Fehler ist außerdem für sich genommen ein
Argument: reine Logik versagt reproduzierbar, Analoges nicht. Kopplung, Flanken,
Laufzeiten — das versagt sporadisch.

#### `vdp_lobyte2`, zweite Fassung: mitteln statt berichten

Deshalb berichtet das ROM jetzt nicht mehr einmal, sondern läuft in Runden, bis
der Strom ausgeht. Es zählt Fehlschläge je Kopie, sättigt bei 255, und frischt
das LCD alle sechzehn Runden auf. Die Zahlen setzen sich mit wachsender
Rundenzahl, und der Rundenzähler sagt, wie viel Belege dahinterstehen.

```
N=0140
.....*A.*******
.....*A.*******
LO 40-B8 ST 8
```

Ein Punkt heißt „nie fehlgeschlagen", eine Ziffer die Anzahl, ein Stern
„sechzehn oder mehr". Zusammen mit `N` ist beides etwas wert; einzeln nichts.
Eine Minute laufen lassen, dann ablesen.

#### Gemessen am Brett: keine Brücke

`A6`/`A7`: 270 kΩ. `A8`/`A9`: 270 kΩ. `A10`/`A11`: 270 kΩ. Auf **jedem**
Nachbarpaar derselbe Wert — das ist der Leckpfad durch die CMOS-Eingänge am
Bus, nicht eine Verbindung. Eine echte Zinnbrücke läge bei einigen hundert Ohm
und auf genau einem Paar. **Die Kopplungsthese ist damit erledigt**, und zwar
ohne einen weiteren Brennvorgang.

#### Und ein dritter Denkfehler im Aufbau

Eine Beispielausgabe der ersten Fassung:

```
00FFEE67FFFF6731
00FF4501FFFFDD65
```

Struktur ist da: `$40`/`$48` fallen in beiden Sätzen nie durch, `$50`/`$58` und
`$80`–`$98` fallen in beiden immer durch. Dazwischen widersprechen sich die
Zeilen: bei `$60` steht 14 gegen 4, bei `$70` 6 gegen 0, bei `$A0` 6 gegen 13.

Der Grund liegt wieder im Aufbau. Die Proben laufen hintereinander weg und
kosten alle gleich viele Takte, also bestimmt die **Nummer** einer Probe, wo im
VDP-Bild sie landet — und die Nummer ist mit dem niederwertigen Byte gekoppelt.
Satz A sind die Nummern 0–15, Satz B die Nummern 16–31, also eine andere Phase.
Dass die zwei Zeilen auseinanderlaufen, hat damit eine viel einfachere
Erklärung als „die Seite zählt".

Behoben, indem jede Probe auf den Bildrücklauf wartet: Statusregister lesen
(löscht das Merkbit und nebenbei das Flipflop am Steuerport), pollen bis es
wieder gesetzt ist, dann sofort die Probe. Jede Probe beginnt damit an
derselben Stelle im Bild. Der Poll ist auf fünfzehn Takte gepolstert, weil eine
enge Leseschleife den Chip öfter träfe als die acht Mikrosekunden erlauben.

Eine Runde dauert dadurch etwa eine halbe Sekunde, also wird nach jeder Runde
neu gezeichnet.

Gebrannt, 141 Runden:

```
N=008D
..**.1.1****.1..     Satz A
..**....****.1..     Satz B
```

**Die beiden Zeilen sind zusammengelaufen.** Durchgefallen sind `$50`, `$58`,
`$80`, `$88`, `$90`, `$98`; alles andere höchstens einmal in 141 Runden. Damit
steht zweierlei fest: die **Seiten sind unschuldig** — zwei verschiedene Seiten
geben dieselbe Antwort —, und das niederwertige Byte entscheidet **zuverlässig**,
sobald die Phase festgehalten wird.

Nur ist es kein Bitmuster. Weder ein einzelnes Adressbit noch ein Bitpaar, an
keinem Offset in der Probe, trennt die durchgefallenen von den bestandenen
Werten; die Zahl der gleichzeitig umschaltenden Adressleitungen auch nicht. Was
die Karte zeigt, sind zwei Bänder, ungefähr `$50`–`$5F` und `$80`–`$9F`, und
eine Abtastung alle acht Bytes kann deren Ränder nicht auflösen.

#### `rom/vdp_sweep` — jedes niederwertige Byte, aus dem RAM

Also nicht jedes achte, sondern jedes. Das verlangt eine Probe, die sich
verschieben lässt, und diese lässt sich verschieben: sie enthält keinen Bezug
auf sich selbst, nur absolute Verweise auf die VDP-Ports und auf zwei
Zero-Page-Bytes. Sie wird nach `$2000+LO` kopiert und dort aufgerufen, für `LO`
von `$40` bis `$FF`.

Aus dem RAM zu laufen beantwortet nebenbei eine zweite Frage umsonst. Fallen
dieselben niederwertigen Bytes durch wie aus dem ROM, dann ist es der Adressbus
und nicht der Speicherbaustein. Ist das RAM überall sauber, ist es etwas am
Zeitverhalten des ROM, und das wäre eine andere Suche.

Jede Probe wartet weiterhin auf den Bildrücklauf. Eine Runde dauert damit rund
vier Sekunden.

```
N=000C 40-FF
....****........     $40-$7F
****............     $80-$BF
................     $C0-$FF
```

Ein Zeichen deckt vier niederwertige Bytes ab: Punkt heißt alle vier bestanden,
Stern alle vier durchgefallen, **Plus heißt, dass der Rand eines Bandes in
diesem Zeichen liegt** — und die Ränder sind das Gesuchte.

Gebrannt, `N=0015`: **einundzwanzig Runden über 192 Adressen, kein einziger
Fehlschlag.** Aus dem RAM fällt kein niederwertiges Byte durch.

#### Aber schon wieder zwei Änderungen auf einmal

So verlockend „RAM sauber, ROM nicht" klingt — es ist noch nicht ablesbar,
denn zwischen den beiden ROMs haben sich zwei Dinge geändert, und beide sind
meine. Der Sweep läuft aus dem RAM, **und** er benutzt eine andere Probe:
geradeaus durchlaufender Code mit `nop`s als Pause, während `vdp_lobyte2` zwei
Unterprogramme in sich selbst aufrief. Beides kann der Auslöser sein.

#### `rom/vdp_romram` — eine Probe, zwei Speicher

Deshalb ändert dieser Brand genau eines. Die verschiebbare Probe des Sweeps
wird für beide Zeilen benutzt. Sechs Kopien davon liegen im ROM auf den
niederwertigen Bytes `$50`, `$80`, `$90` und `$98`, die durchfallen, sowie
`$40` und `$60`, die bestehen — am gebauten Image als byteidentisch nachgeprüft.
Dieselben sechs niederwertigen Bytes werden zusätzlich aus dem RAM gefahren,
aus einer Kopie auf `$2000+LO`. Gleiche Befehle, gleiche Pausen, gleiche
Reihenfolge, gleiche Synchronisierung auf den Bildrücklauf; der einzige
Unterschied zwischen den Zeilen ist, aus welchem Baustein die Bytes geholt
werden.

```
N=0020
R ****..
M ......
50809098 4060
```

* **ROM fällt durch, RAM sauber** → es ist der Speicherbaustein oder dessen
  Zeitverhalten, nicht der Adressbus. Der Bus führt in beiden Zeilen dieselben
  Adressen.
* **beide sauber** → die geradeaus durchlaufende Probe reicht nicht, um es
  hervorzurufen, und es kommt auf `jsr` und `rts` an, die `vdp_lobyte2` hatte.
* **beide fallen durch** → doch der Adressbus, und das Schweigen des Sweeps
  braucht eine andere Erklärung.

Gebrannt, `N=017B` — 379 Runden:

```
N=017B
R .***.*
M ......
50809098 4060
```

| `LO` | ROM | RAM | mit der `jsr`-Probe |
|---|---|---|---|
| `$50` | . | . | durchgefallen |
| `$80` | * | . | durchgefallen |
| `$90` | * | . | durchgefallen |
| `$98` | * | . | durchgefallen |
| `$40` | . | . | bestanden |
| `$60` | * | . | bestanden |

Zwei Dinge stehen damit.

**Das RAM ist sauber, das ROM nicht** — bei gleichen Befehlen, gleicher
Adress-Endung, gleicher Phase. Der einzige verbleibende Unterschied ist der
Baustein, aus dem geholt wird. Einschränkung, die dazugehört: auf dieser
Platine liegt RAM unter `$8000` und ROM darüber, „ROM gegen RAM" ist also
zwangsläufig auch „`A15`=1 gegen `A15`=0", und der VDP liegt seinerseits bei
`A15`=1. Trennen lässt sich das auf dieser Platine nicht.

**`$50` und `$60` haben getauscht.** Mit der Probe aus Unterprogrammen fiel
`$50` durch und `$60` nicht, mit der geradeaus laufenden ist es umgekehrt. Also
entscheidet nicht die Anfangsadresse des Blocks, sondern wo die einzelnen
Befehle darin landen — was auch erklärt, warum kein Bitmuster auf die
Blockadresse passt.

#### Was eigentlich zurückkommt

Sechs Brände lang wurde nur gezählt, ob etwas zurückkommt, nie was. Das ist die
nächste Frage, und sie kostet keine neue Probe: dieselbe Fassung zeigt jetzt
zusätzlich die zuletzt gelesenen zwei Bytes einer ROM-Kopie, die durchfällt
(`$90`), und einer, die es nicht tut (`$40`).

```
N=0080
R .***.*
M ......
90 EF CB 40 5A A5
```

Geschrieben wurde `$5A $A5`. Was stattdessen dasteht, sagt die Art des Fehlers:

* **`A5 5A`, vertauscht** → das Flipflop am Steuerport ist verrutscht.
* **ein oder zwei Bits daneben** → der Datenbus, und dann ist Buskonkurrenz mit
  dem langsam abschaltenden ROM die naheliegende Erklärung.
* **beliebiger Müll** → gelesen wurde an einer ganz anderen VRAM-Adresse, das
  Adresspaar ist also gar nicht angekommen.
* **wechselt von Runde zu Runde** → analog, nicht logisch.

Gebrannt, und es bleibt dauerhaft stehen:

```
90 A5 20   40 5A A5
```

**Das ist kein Müll, das ist ein Versatz um genau eins.** Geschrieben wurde
`$5A` nach `$3FFE` und `$A5` nach `$3FFF`. Zurückgelesen ab `$3FFE` kommt
`A5 20`: das erste gelesene Byte ist der *zweite* geschriebene Wert, und das
zweite ist der Inhalt von `$0000`, weil der VRAM-Zeiger bei `$4000` umläuft.
Der Lesezeiger stand also auf `$3FFF` statt auf `$3FFE`. Reproduzierbar, ohne
Rauschen.

Zwei Ursachen kommen dafür in Frage, und sie sind unterscheidbar:

* Das niederwertige Adressbyte kam als `$FF` statt `$FE` an — ein einzelnes
  Datenbit auf dem Weg zum Steuerport.
* Es gab einen Zugriff zu viel auf den Datenport, der den Zeiger einmal extra
  weitergestellt hat.

#### Daten, die ihre eigene Adresse verraten

Zwei Bytes sind zu wenig, um das zu trennen. Also schreibt die Probe jetzt
sechzehn Bytes nach `$3FF0`–`$3FFF`, und **jedes Byte ist gleich seiner eigenen
niederwertigen Adresse**: `$F0` nach `$3FF0`, `$F1` nach `$3FF1` und so fort.
Danach liest sie vier Bytes ab `$3FF0` zurück.

Damit sagt jedes gelesene Byte, woher es kommt:

```
N=0040 R .***.* M ......
B 90 F1F2F3F4
G 40 F0F1F2F3
```

* `F0F1F2F3` → alles richtig.
* `F1F2F3F4` → der Lesezeiger startete eins zu hoch; das Schreiben war in
  Ordnung.
* `F1F2F3F4` **und** die guten Kopien zeigen dasselbe → dann liegt es nicht an
  der Adresse.
* Werte, die nicht aufeinander folgen → der Zeiger springt, und dann ist es
  weder ein Bit noch ein Zugriff zu viel.
* `EFF0F1F2` → eins zu *niedrig*, was das Schreiben verschoben hätte.

`B` zeigt die erste ROM-Kopie, die in dieser Runde durchfällt, mit ihrem
niederwertigen Byte davor; `G` zeigt `$40`, das bisher immer bestanden hat.

Gebrannt:

```
B 00 FFAFCB49
G 40 F0F1F2F3
```

`B 00` heißt, dass gar keine ROM-Kopie durchgefallen ist — `$00` ist keins der
sechs niederwertigen Bytes, und die vier Bytes daneben sind uninitialisiertes
RAM, weshalb sie unverändert stehen bleiben. Mit dieser Probe versagt keine
Adresse mehr.

#### Woran es hängt: an der Bauform der Probe

| Probe | Größe | fällt durch bei |
|---|---|---|
| A, mit `jsr`-Unterprogrammen | 62 B | `$50 $58 $80 $88 $90 $98` |
| B, geradeaus, zwei Bytes | 69 B | `$60 $80 $90 $98` |
| C, geradeaus, 16er-Schleife | 82 B | keiner |

Dreimal derselbe Zweck, dreimal ein anderes Ergebnis. Es ist also nicht die
Adresse eines Blocks, sondern wo die einzelnen Befehle darin liegen — und mit
Probe C liegt offenbar keiner mehr ungünstig.

Was über alle Brände hinweg steht:

* Aus dem **RAM** fällt nie etwas durch, aus dem **ROM** schon — bei
  buchstäblich denselben Bytes.
* Das eine saubere Symptom war ein **Lesezeiger genau eins zu hoch**.
* Der Fehler ist an manchen Adressen völlig reproduzierbar und an anderen
  sporadisch.

Das ist zusammen das Bild eines Zeitproblems am Bus, kein Logikfehler, und es
weiter einzugrenzen braucht ein Oszilloskop an `/CS`, `/OE`, φ2 und dem
Datenbus während eines VDP-Schreibzugriffs aus einer schlechten Adresse. Ein
weiterer Brennvorgang bringt dafür nichts mehr.

#### Was stattdessen jetzt im Baum steht: eine Zusicherung

Solange das offen ist, muss die laufende Anordnung halten — und die hält
bislang aus Versehen. `vdp_wait` liegt auf `$F05D` nur deshalb, weil `msbasic.o`
zufällig `$45D` Bytes vor ihm zu `SDCODE` beiträgt. Jede Änderung an
`db6502_sdbasic.s` oder an `CLS` verschiebt ihn, und das erste Anzeichen wäre
ein Bildschirm voller falscher Zeichen auf einer Platine, die eine Stunde vorher
lief.

In `rom/microsoft_basic/standalone.s` steht deshalb jetzt:

```asm
        .import vdp_wait
        .assert vdp_wait = $F05D, lderror, "vdp_wait has moved - new code belongs in EXTCODE2, see MEMORY_MAP.md 5.5"
```

Projektlokal, also ohne Wirkung auf `os1` und die Prüf-ROMs, und sie erzeugt
kein einziges Byte — das Image bleibt byteidentisch zur Referenz. Nachgeprüft
ist auch, dass sie auslöst: ein einzelnes Füllbyte vorn in `SDCODE` bringt

```
standalone.s:43: Error: Assertion failed: vdp_wait has moved - new code belongs in EXTCODE2, see MEMORY_MAP.md 5.5
```

Wenn sie zuschlägt, ist die Antwort **nicht**, die Zahl anzupassen, sondern den
neuen Code nach `EXTCODE2` zu legen, das hinter allem anderen sitzt und nichts
verschiebt.

#### Warum `os1` nie betroffen war

`os1` hat in dieser Sache nie Ärger gemacht, und der Grund steht in seiner
Mapdatei: sein `vdp_wait` liegt auf **`$EC00`**. In `os1` trägt `msbasic.o`
nichts zu `SDCODE` bei, also steht `vdp.o` ganz vorn im Block und erbt dessen
Seitenanfang. Niederwertiges Byte `$00` — und `$00` war in jeder gemessenen
Karte durchweg gut.

Die naheliegendere Vermutung, `os1` initialisiere den Bildschirm einfach viel
später (zweimal eine Sekunde Wartezeit vor der ersten Ausgabe, und der VDP kommt
erst in `_run_shell`), trägt dagegen nicht: in `vdp_romram` liefen dieselben
Fehlschläge über 379 Runden, also mehrere Minuten nach dem Einschalten,
unverändert weiter. Ein Aufwärmeffekt ist es nicht.

#### `rom/vdp_scope` — für den Logikanalyzer

Die Frage, die ein Analyzer in einer einzigen Aufnahme beantwortet: kam am
Steuerport `$FE` an oder `$FF`, oder gab es einen Zugriff mehr, als das Programm
ausgelöst hat? Das erste wäre eine Datenleitung — `D0` — und damit
Buskonkurrenz; das zweite ein Strobe, den niemand programmiert hat.

Das ROM legt die gute und die schlechte Kopie unmittelbar nacheinander in ein
Triggerfenster, mit einer Marke auf der LED-Leitung (Bit 7 von VIA2 Port B, von
`_blink_init` ohnehin als Ausgang gesetzt):

```
Marke hoch   Kopie auf niederwertigem Byte $40 - läuft
Marke tief   kurze Lücke
Marke hoch   Kopie auf niederwertigem Byte $90 - läuft nicht
Marke tief   rund 20 ms Ruhe
```

Auf die erste steigende Flanke nach der Ruhephase triggern, dann liegen beide
Proben in einem Fenster, die funktionierende zuerst. Die beiden Kopien sind am
gebauten Image als byteidentisch nachgeprüft; der einzige Unterschied ist die
Adresse, aus der sie geholt werden.

Das LCD zählt nebenher mit, damit sichtbar bleibt, dass die schlechte Kopie
während der Aufnahme wirklich versagt.

#### Gemessen: der VDP bekommt Lesezugriffe, die niemand ausgelöst hat

Aufgenommen mit 24 MHz auf 1 MHz Bustakt, also 42 ns Auflösung — bei den ersten
1 MHz fehlten 63 % der Strobes, das war unbrauchbar. 286 verwertbare
Markerpaare. `common/srglitch.py` wertet die `.sr`-Datei aus:

```
die Kopie, die laeuft:
  /CSW           {6: 286}
  /CSR, echt     {2: 286}
  /CSR, Glitches {0: 136, 1: 130, 2: 19, 3: 1}
die Kopie, die versagt:
  /CSW           {6: 286}
  /CSR, echt     {2: 286}
  /CSR, Glitches {2: 5, 3: 87, 4: 70, 5: 61, 6: 63}
```

Die Breiten der `/CSR`-Impulse zerfallen in zwei Gruppen ohne irgendetwas
dazwischen: **900–1100 ns** und **unter 100 ns**. Die breiten sind die
Lesezugriffe des Programms — davon gibt es in beiden Fenstern exakt zwei, das
Programm tut also genau das Richtige. Die schmalen sind **Störimpulse von etwa
42 ns**, und sie liegen alle **auf der abfallenden Flanke von `/CSW`**: Median
`+0 ns`, 5.–95. Perzentil `+0 ns`.

`/CSW` selbst ist tadellos: immer genau sechs, immer 958–1000 ns breit.

**Damit ist die Ursache gefunden.** Jedes Schreiben auf den VDP erzeugt beim
Beenden einen kurzen Lese-Strobe. Das ist ein Wettlauf in der Auswahllogik: wenn
der Schreibzyklus endet, geht `R/W` wieder auf hoch, *bevor* die Auswahl des VDP
verschwindet — für diesen Moment ist „VDP ausgewählt und Lesen" wahr, und
`/CSR` zuckt. Ein solcher Zugriff auf den Datenport stellt den VRAM-Zeiger
weiter; einer auf den Steuerport liest das Statusregister und setzt dabei das
Schreib-Flipflop zurück.

Und **jede einzelne Beobachtung der letzten neun Brände fällt damit an ihren
Platz**:

| Beobachtung | Erklärung |
|---|---|
| Lesezeiger genau eins zu hoch | ein Störimpuls auf dem Datenport |
| zerstörter Zeichensatz | 1024 Schreibzugriffe, jeder mit der Chance auf einen |
| hängt an der Adresse | der Wettlauf entscheidet sich daran, welche Adresse als Nächstes geholt wird, und das ist der nächste Befehl |
| kein Bitmuster in der Adresse | es ist Laufzeit, keine Logik |
| ROM ja, RAM nein | anderer Baustein, andere Flankenzeiten am selben Bus |
| an manchen Adressen sporadisch | ein Wettlauf an der Grenze |
| Taktzahlen erklären nichts | erklären sie auch nicht — es ist die Adresse selbst |
| `os1` nie betroffen | sein `vdp_wait` liegt auf `$EC00`, und diese Lage gewinnt den Wettlauf |

#### Was in Hardware zu ändern ist

`/CSR` darf nicht zusagen können, während `/CSW` gerade endet. Sauber ist:

```
/CSR = NICHT (VDP_AUSGEWAEHLT UND R/W UND phi2)
/CSW = NICHT (VDP_AUSGEWAEHLT UND NICHT R/W UND phi2)
```

Steht in `/CSW` bereits φ2 und in `/CSR` nicht, ist genau das der Fehler: mit φ2
im `/CSR`-Term kann der Impuls beim Fallen von φ2 nicht mehr entstehen. Zu
prüfen ist also das Gatter, das `/CSR` erzeugt.

Ein Nachtrag zur Messung: der `MODE`-Kanal war unbrauchbar (41 Millionen
Flanken, mehr als es Buszyklen gibt — Masseproblem an der Klemme). Deshalb ist
nicht gemessen, ob die Störimpulse den Daten- oder den Steuerport treffen. Für
die Abhilfe macht das keinen Unterschied.

#### Der Verursacher: ein 74HC138 ohne Taktfreigabe

`/CSW` und `/CSR` kommen aus **einem einzigen 74HC138**. Eine zweite Aufnahme,
diesmal mit den Freigabepins des Dekoders (`G1` Pin 6, `/G2A` Pin 4, `/G2B`
Pin 5), zeigt den Vorgang Takt für Takt:

```
  t(ns)  phi2  R/W  /CSW  /CSR  G1  /G2A  /G2B
   -42     0    0    0     1    1    0     0     Schreibzugriff laeuft
    +0     0    1    1     0    1    0     0     R/W geht hoch, Freigabe steht noch
   +42     0    1    1     1    1    1     0     /G2A geht weg, Dekoder gesperrt
```

**`R/W` steigt ein Sample, bevor `/G2A` die Freigabe wegnimmt.** In genau diesem
Fenster ist der '138 noch freigegeben und `R/W` sagt bereits „lesen" — also
zieht er `/CSR` auf tief. Das ist der Störimpuls, direkt beobachtet.

Und `/G2A` ist die Adressdekodierung: sie geht weg, wenn der Adressbus auf den
nächsten Befehl weiterrückt. **Wie schnell das geschieht, hängt daran, welche
Adresse als Nächstes anliegt** — damit ist auch der letzte Rest der
Adressabhängigkeit erklärt, und zwar als Laufzeit, nicht als Logik.

Zwei Zahlen aus derselben Aufnahme belegen die eigentliche Ursache:

* **Kein Freigabepin schaltet im Takt.** Bei 3 991 193 Buszyklen hat `phi2`
  99,9 % der erwarteten Flanken, `G1` 4,5 %, `/G2A` 3,1 %, `/G2B` 0,7 %. Der
  '138 ist also **nicht taktsynchron freigegeben**.
* **`/CSW` ist 958 ns von 1000 ns breit**, deckt also praktisch den ganzen
  Buszyklus ab statt nur die Datenphase.

Der Fehler ist damit kein Grenzfall, den man verschieben müsste, sondern eine
fehlende Qualifizierung: die Auswahl des VDP steht an, solange die Adresse
anliegt, und was der '138 in dieser Zeit auf seine Ausgänge legt, entscheidet
allein `R/W`.

Zählung über 97 Markerpaare, mit korrekt angeschlossenem `R/W`:

| | `/CSW` | `/CSR` echt | Störimpulse |
|---|---|---|---|
| Kopie `$40`, läuft | immer 6 | immer 2 | `{0: 88, 1: 9}` |
| Kopie `$90`, versagt | immer 6 | immer 2 | `{1: 6, 2: 21, 3: 29, 4: 14, 5: 24, 6: 3}` |

#### Die Abhilfe

Beide Ausgänge mit φ2 nachsperren:

```
/CSW' = /CSW_138  ODER  NICHT phi2
/CSR' = /CSR_138  ODER  NICHT phi2
```

Ein 74HC32 und ein Inverter. Der Störimpuls entsteht, während φ2 tief ist — am
Nachgatter ist `NICHT phi2` dann bereits hoch und zwingt beide Strobes
inaktiv. Die echten Zugriffe liegen in der φ2-Hochphase und laufen unverändert
durch. Nebenbei schrumpft der Strobe von 958 ns auf die Datenphase, was der
TMS9918A ohnehin erwartet.

#### Am φ2-Ausgang der CPU nachgemessen

Die vorherige Aufnahme lag am Takteingang. Am `PHI2O`-Ausgang gemessen ändert
sich nichts Wesentliches, und es kommen drei harte Zahlen dazu:

* **`phi2O` ist 292 ns von 1000 ns hoch**, also 29 % Tastgrad. Das ist auch am
  Ausgang so, nicht nur am Eingang.
* **100 % der Störimpulse liegen in der φ2-Tiefphase.** Eine Sperre gegen φ2
  fängt damit jeden einzelnen.
* **Von 38 950 `/CSR`-Impulsen sind 38 552 Störimpulse — 99 %.** Fast jeder
  Lese-Strobe, den der VDP sieht, ist keiner. `/CSW` dagegen glitcht in 3194
  Impulsen **kein einziges Mal**; der Wettlauf entsteht nur beim Übergang
  Schreiben→Lesen am Zyklusende, nicht umgekehrt.

Die φ2-Hochphase liegt bei `+625 ns` bis `+917 ns` innerhalb des 958 ns langen
`/CSW`-Impulses. Der Strobe beginnt also 625 ns *bevor* φ2 steigt — das ist die
fehlende Taktfreigabe, direkt abgelesen — und endet 41 ns nachdem φ2 gefallen
ist. In diesem Schwanz sitzt der Störimpuls.

#### Warum das Nachsperren nicht ohne Weiteres genügt

Nach `strobe' = strobe ODER NICHT phi2` wäre der Strobe **292 ns** breit statt
958 ns. Für `/CSW` ist das unkritisch: der 9918 übernimmt die Daten an der
steigenden Flanke, und die Daten stehen dort längst.

Für `/CSR` ist es das nicht. Heute bekommt der Chip 958 ns Zeit, seine Daten
herauszugeben; die CPU übernimmt sie an der fallenden Flanke von φ2. Nach dem
Nachsperren blieben ihm 292 ns minus der Vorhaltezeit der CPU. Ob das reicht,
hängt an der Zugriffszeit des konkreten Bausteins — beim TMS9918A liegt sie in
derselben Größenordnung, und das ist zu knapp, um es ungeprüft zu löten.

**Der Tastgrad ist deshalb das eigentliche Hindernis.** Ein 6502-Takt hat
üblicherweise rund 50 %; hier sind es 29 %. Mit einem symmetrischen Takt wären
es rund 500 ns, und die Sperre ginge ohne Sorge. Also in dieser Reihenfolge:

1. **Takt-Tastgrad prüfen** — und zwar mit einem analogen Oszilloskop, denn ein
   Logikanalyzer mit fester Schwelle meldet bei langsamen Flanken zu kurze
   Hochphasen. Ist er wirklich 29 %, gehört das ohnehin in Ordnung gebracht.
2. **Dann φ2 in die Auswahl** — als Freigabe am '138, wenn ein Eingang frei
   gemacht werden kann, sonst als Nachgatter an beiden Ausgängen.
3. **Danach die Zugriffszeit gegen den verbliebenen Strobe rechnen**, bevor
   gelötet wird.

Ein `R/W`-Verzögerungsglied ist übrigens **keine** Abhilfe, auch wenn es
naheliegt: es würde den Störimpuls vom Zyklusende an den Zyklusanfang
verschieben, wo `R/W` dann veraltet ist, während die Adressdekodierung schon
zusagt. Der Wettlauf bliebe, nur mit vertauschten Rollen.

#### Der Tastgrad ist erklärt und behoben

Die 29 % kamen von der Takterzeugung: ein 4-MHz-Oszillator und ein CD4017 als
Teiler. Der CD4017 gibt je Zählschritt einen Ausgang frei, bei Teilung durch
vier also **eine** Hochphase auf **drei** Tiefphasen — 25 % von Bauart wegen,
kein Fehler in der Schaltung, sondern eine Eigenschaft des Teilers. Ersetzt
durch einen echten 1-MHz-Oszillator ohne Teiler.

Nachgemessen: `phi2O` hat jetzt **Periode 1,000 µs, hoch 500 ns, Tastgrad
50 %**.

#### Was der symmetrische Takt ändert — und was nicht

**Die Störimpulse bleiben unverändert.** Über 111 Markerpaare:

| | `/CSW` | `/CSR` echt | Störimpulse |
|---|---|---|---|
| Kopie `$40`, läuft | immer 6 | immer 2 | `{0: 102, 1: 9}` |
| Kopie `$90`, versagt | immer 6 | immer 2 | `{1:7, 2:29, 3:21, 4:26, 5:25, 6:3}` |

Das war zu erwarten: der Wettlauf im '138 hängt an Laufzeiten, nicht an der
Taktform. Wer gehofft hatte, der Takt sei die Ursache, liegt falsch — er war
nur das Hindernis für die Abhilfe.

**Und genau das ist jetzt weg.** Die φ2-Hochphase liegt bei `+417 ns` bis
`+917 ns` im 958 ns langen Strobe, ein nachgesperrter Strobe wäre also
**500 ns** breit statt 292 ns. Das ist ein gewöhnliches 6502-Zeitbudget, und
die Zugriffszeit des 9918 passt bequem hinein.

99,6 % der Störimpulse liegen in der φ2-Tiefphase; die beiden Ausnahmen von 457
liegen außerhalb der Messfenster und bei gesperrtem Dekoder, sind also Rauschen.
Im typischen Fall ist φ2 bereits **83 ns** tief, bevor der Störimpuls kommt —
die Sperre greift mit Reserve, nicht auf Kante.

Damit ist der Umbau geklärt: **φ2 in die Auswahl des VDP**, entweder als
Freigabe am '138 oder als Nachgatter an `/CSW` und `/CSR`.

#### Warum ein Verzögerungsglied an `R/W` nicht geht — gemessen

Naheliegend wäre, statt eines Gatters einfach `R/W` zum '138 zu verzögern, bis
die Freigabe weg ist. Die Aufnahme sagt, dass das nicht geht:

```
ZYKLUSBEGINN   R/W wird tief   42 ns VOR   /G2A wird tief
ZYKLUSENDE     R/W wird hoch   42 ns VOR   /G2A wird hoch
```

`R/W` eilt an **beiden** Enden gleich weit vor. Damit das Ende sauber wird,
müsste die Verzögerung größer als dieser Vorsprung sein; damit der Anfang
sauber bleibt, kleiner. Jede feste Verzögerung repariert die eine Flanke und
zerlegt die andere um denselben Betrag.

#### Der Umbau: ein 74HC00

Kein 74HC32 zur Hand, und der '00 ist ohnehin die bessere Wahl — vier Gatter,
ein Gehäuse, und φ2 muss nicht invertiert werden:

```
Gatter 1 (Pin 1,2 -> 3)    NAND(/CSW_138, /CSW_138)   = Inverter
Gatter 2 (Pin 4,5 -> 6)    NAND(Pin 3, phi2)          -> /CSW zum VDP
Gatter 3 (Pin 9,10 -> 8)   NAND(/CSR_138, /CSR_138)   = Inverter
Gatter 4 (Pin 12,13 -> 11) NAND(Pin 8, phi2)          -> /CSR zum VDP
```

Pin 14 an +5 V, Pin 7 an GND, 100 nF dazwischen. φ2 ist `PHI2O`, Pin 39 des
65C02.

#### Gemessen nach dem Umbau: null

Sechs Sekunden Aufnahme, 155 Markerpaare:

| | `/CSW` echt | Störimpulse | `/CSR` echt | Störimpulse |
|---|---|---|---|---|
| Kopie `$40` | immer 6 | **`{0: 155}`** | immer 2 | **`{0: 155}`** |
| Kopie `$90` | immer 6 | **`{0: 155}`** | immer 2 | **`{0: 155}`** |

Die Strobes sind jetzt 500 ns breit statt 958 — sie liegen in der Datenphase,
wo sie hingehören. Von den 43 700 Störimpulsen je Aufnahme sind **null**
übrig; die 144 kurzen Impulse, die das Skript im ganzen Mitschnitt noch findet,
liegen sämtlich in der ersten Millisekunde, also im Einschwingen des Analyzers.

Die Kopie auf `$90`, die vorher in jedem einzelnen Fenster versagt hat,
verhält sich jetzt Byte für Byte wie die auf `$40`.

#### Die Gegenprobe am eigentlichen Patienten

Das Steckbrett ist repariert, aber bewiesen ist damit erst, dass die
Störimpulse weg sind — nicht, dass BASIC an einer früher schlechten Adresse
läuft. Dafür wird das Image gebaut, das viermal einen schwarzen Bildschirm
gab, bitgleich: `VDPCODE` auf `$E3B7`, `md5 930be09d5751eefc481b0983eee4eaec`.

Gebrannt, mehrfach kalt gestartet: **Bild ist da.** Dasselbe ROM, das viermal
schwarz blieb, läuft.

#### Erledigt

Damit ist die Untersuchung abgeschlossen, und das Ergebnis ist, dass die
Software nie schuld war. Was jetzt gilt:

* **Die Regel „neuer Code gehört nach `EXTCODE2`" ist aufgehoben.**
  `db6502_sdbasic.s`, `CLS` und alles andere in `SDCODE` dürfen wieder wachsen,
  Bibliotheksmodule dürfen sich verschieben, Statements dürfen dort stehen, wo
  sie hingehören. `EXTCODE2` bleibt als Block bestehen — der Code darin ist ja
  in Ordnung —, aber es ist kein Zwang mehr.
* **Die Zusicherung `vdp_wait = $F05D` in `standalone.s` ist entfernt.** Sie
  hatte genau einen Zweck, und der ist entfallen.
* **`VDPCODE` ist aus `firmware.ext.cfg` verschwunden.** Die VDP-Routinen liegen
  wieder in `SDCODE`, wo sie hingehören, und `microsoft_basic` ist byteidentisch
  mit der eingefrorenen Referenz.
* **Die Taktung der VDP-Zugriffe bleibt.** Die acht Mikrosekunden, die der
  TMS9918A verlangt, sind unabhängig von diesem Fehler real; die Korrekturen
  vom 25.08.2026 (5.5, erster Teil) waren richtig und bleiben.

Was von der Untersuchung im Baum bleibt, ist die Prüfung: `rom/vdp_scope`
erzeugt die Aufnahme, `common/srglitch.py` wertet sie aus. Wer am Adressdekoder
etwas ändert, kann damit in zwei Minuten nachsehen, ob die Störimpulse wieder
da sind.

#### Was diese Jagd gekostet hat, und was sie gelehrt hat

Dreizehn Brennvorgänge und sechs Prüf-ROMs, und der Fehler war die ganze Zeit
ein Gatter. Drei Lehren, die beim nächsten Mal Zeit sparen:

**Dreimal hat ein sauberes Muster gepasst und war trotzdem falsch** — erst eine
einzelne Verzweigung, dann `A7` gegen `A6`, dann das niederwertige Byte als
Bitmuster. Jedes davon starb an einem Brand, der gebaut wurde, um es zu
*widerlegen*, nicht um es zu bestätigen. Bei wenigen Datenpunkten passt fast
immer irgendetwas.

**Viermal lag der Denkfehler im eigenen Messaufbau**: Seite an das
niederwertige Byte gekoppelt, Probennummer an die Bildphase gekoppelt, RAM und
Probenform gleichzeitig getauscht, Füller vor mehr Bewohner gelegt als
beabsichtigt. Wenn eine Messung der vorigen widerspricht, ist zuerst der
Aufbau verdächtig, nicht die Schaltung.

**Und die Frage „was kommt eigentlich zurück" hätte sechs Brände früher gestellt
gehört.** Sechs Durchgänge lang wurde nur gezählt, *ob* etwas zurückkommt. Der
erste Blick auf die tatsächlichen Bytes ergab `A5 20` statt `5A A5` — ein
Versatz um genau eins — und von da an ging es geradeaus zum Störimpuls.

#### Aufgeräumt

`rom/vdp_lobyte`, `rom/vdp_lobyte2`, `rom/vdp_sweep` und `rom/vdp_romram` sind
aus dem Baum, mit ihnen 48 feste Segmente aus `firmware.ext.cfg`, die sich
zuletzt gegenseitig im Weg standen. Ihre Ergebnisse stehen hier, ihre Quellen
in der Historie. Geblieben sind `rom/vdp_scope` und `common/srglitch.py` —
zusammen die Prüfung, mit der sich das jederzeit wiederholen lässt.

#### Und die Messung, die kein ROM braucht

Wenn die Kopplung stimmt, liegt sie zwischen zwei benachbarten Adressleitungen,
und die beiden Kandidatenpaare sind `A6`/`A7` und `A10`/`A11`. Beide sind am
6502 wie am ROM Nachbarpins. Ein Durchgangsprüfer im stromlosen Zustand kostet
nichts und kann das hier beenden: einige hundert Ohm zwischen zwei
Adressleitungen sind kein Zufall.

#### Die vollständige Liste der Zugriffspaare

Nachdem das Scrollen als letztes umkippte — Text lief sauber bis zum unteren
Rand, dann nur noch Müll — ist der Baum einmal komplett durchgesehen. Jedes Paar
von Schreibzugriffen auf den Steuerport `$8081`, mit dem Abstand zwischen den
beiden Buszugriffen bei 1 MHz:

| Stelle | vorher | Stand |
|---|---|---|
| `vdp_write_register` | 16 µs | getaktet, war immer so |
| `vdp_write_address` | 16 µs | getaktet, war immer so |
| `load_vram_char_position` | **9 µs** | getaktet 25.08. — jedes ausgegebene Zeichen |
| `vdp_set_vram_addr` (Makro) | **2 µs** | getaktet 25.08. — nur `CLS` |
| `vdp_vram_read_buffer` | **9 µs** | getaktet 25.08. — Scrollen |
| `vdp_vram_write_buffer` | **9 µs** | getaktet 25.08. — Scrollen |
| `vdp_init_text_mode` | 4 µs | tot, im Code gewarnt |
| `vdp_enable_display` | 2 µs | tot, im Code gewarnt |

Gefordert sind acht. Die beiden toten Routinen sind nur deshalb tot, weil der
Kaltstart und `SCREEN 0` über `vdp_boot_registers` und `vdp_boot_enable` gehen,
die von Anfang an getaktet waren — wer sie wieder anfasst, holt den Fehler
zurück, und beide tragen jetzt einen Warnkommentar.

Damit gibt es im Baum keinen ungetakteten Zugriff mehr, den irgendetwas
aufruft.

#### Das Makro, allein

`vdp_set_vram_addr` läuft jetzt über `vdp_write_address`. Zusammen mit dem
`SDCODE`-Versuch gebrannt hat es nichts über sich selbst verraten — der
Zeichensatz war schon beim Einschalten hin, `CLS` damit nicht beurteilbar. Es
geht deshalb noch einmal allein aufs Image: gegen das zuletzt laufende ROM sind
`RODATA`, `BAS_*`, `SDCODE`, `EXTCODE`, `EXTCODE2`, `SYSCALLS` und `VECTORS`
byteidentisch, `CODE` behält Adresse und Länge. Eine Variable.

## 6. Kollisionen — Status

Behoben in Phase 1 (Build `rom/microsoft_basic`, verifiziert gegen die Mapfiles):

| # | Ehemals | Jetzt |
|---|---|---|
| 1 | `sd.s: fat32_workspace = $0200` über `acia_rx_buffer`/`acia_tx_buffer` | Segment `FATBUF` → `$0C00` |
| 2 | `sd.s: buffer = $0400` über `keyboard_buffer`/`lcd_line_buffer`/`text_screen_buffer` | `buffer = __USERRAM_START__` (`$1000`) |
| 3 | `INPUTBUFFER = $0900` im `BSS` | `$0F00` in `BAS_RAM`, per `.assert` abgesichert |
| 4 | MS-BASIC RAM-Probe ohne Obergrenze → schreibt in VDP/VIA/ACIA | `.ifdef DB6502` Limit `$8000` in `init.s` |
| 5 | XMODEM-Empfang ohne Bereichsprüfung | Ladeadresse und Fortschritt auf `$1000`–`$7FFF` begrenzt |
| — | `SYS_RAM` reichte bis `$0EFF`, Überlauf blieb unbemerkt | `SYS_RAM` endet `$09FF`, Überlauf ist jetzt ein ld65-Fehler |

Behoben in Phase 3 (ASCII-`LOAD`/`SAVE`):

| # | Ehemals | Jetzt |
|---|---|---|
| 6 | `INPUTBUFFER = $0E00` → `PUT_NEW_LINE` schrieb `$0EFC`–`$0EFF`, also die letzten vier Bytes von `fat32_workspace` | `INPUTBUFFER = $0F00`, `BAS_RAM` um eine Guard-Page auf `$0E00`–`$0FFF` erweitert |
| 7 | `db6502_sdbasic.s` in `CODE` und `BSS` → `CODE` bis `$E08D`, `RODATA_PA` auf `$EA00`, `vdp_line` auf `$0907`; VDP zeigt nur noch blau | Rumpf in `SDCODE` `$EC00`, Variablen in `BASBUF` `$0E00` — Bibliotheksmodule bleiben auf ihren Adressen (siehe 5.2) |

Phase 4 (`SAVE` legt Dateien an), 2026-08-10 — ohne Kollision, aber nach denselben Regeln:

| # | Änderung | Wo |
|---|---|---|
| — | Allozierender Schreibpfad (Verzeichniseintrag anlegen, Cluster vergeben und freigeben, beide FAT-Kopien nachziehen, FSInfo entwerten) | Neu am Ende von `libfat32.s` in `.segment "SDCODE"`, Variablen in `BASBUF` `$0E22`–`$0E4E`; `fat32_init` und alles in `CODE` blieben unangetastet |

Offen (bewusst zurückgestellt, Loadable-Builds außerhalb des Scope):

| # | Bereich | Kollidiert mit |
|---|---|---|
| 8 | `load/22_msbasic/defines_db6502.s: INPUTBUFFER = $0900` | Firmware-`BSS` |
| 9 | `db6502_extra.s: TXTBUFFER` in Segment `SYSRAM` — im ROM-Build unkritisch (`$0814`–`$0853`, `BSS` folgt danach), beim Loadable-Build läge es auf dem Firmware-`BSS` | Firmware-`BSS` bei Loadable-Build |
| 10 | `load.cfg: USERRAM $30FF+$5000` → Ende `$80FE` | VDP `$8080` |
