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
| `$0E00` | `$0E61` | 98 | Segment `BASBUF`, Teil aus `msbasic.o`: Zustandsvariablen von `db6502_sdbasic.s` (`sd_loadmode`, `sd_savemode`, `sd_fatname`, …), `start_magic`, Zustand der Grafikbefehle und des Grafiktexts |
| `$0E62` | `$0E97` | 54 | Segment `BASBUF`, Teil aus `sd.o`: Variablen des allozierenden Schreibpfads in `libfat32.s` (`fat32_partstart`, `fat32_fatsize`, `fat32_maxcluster`, `fat32_scancluster`, …) |
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
| `$A000` | `$CD39` | 11578 | `CODE` |
| `$CD3A` | `$E029` | 4848 | `RODATA` |
| `$E02A` | `$E0FF` | 214 | frei |
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

ROM frei gesamt 5200 Bytes von 24576.

### 5.1 Build `rom/microsoft_basic`

<!-- mapdoc: microsoft_basic rom -->

| Von | Bis | Bytes | Segment |
|---|---|---|---|
| `$A000` | `$A002` | 3 | `STARTUP` (`jmp init`) |
| `$A003` | `$DAB2` | 15024 | `CODE` |
| `$DAB3` | `$E138` | 1670 | `RODATA` (u. a. VDP-Zeichensatz + Registertabelle) |
| `$E139` | `$E309` | 465 | `BAS_VEC` / `BAS_KEY` / `BAS_ERR` — `BAS_KEY` bei 277 Bytes, die 256er-Grenze ist aufgehoben, siehe 5.3 |
| `$E30A` | `$E6FF` | 1014 | frei — hier lag `RODATA_PA`, siehe 5.4 |
| `$E700` | `$EBE7` | 1256 | `EXTCODE` — Panel, Laufwerks-LED, Fehlertexte, FSInfo-Buchführung, `BLOCKS FREE`, Kaltstart-Leuchte, `SOUND` |
| `$EBE8` | `$EBFF` | 24 | frei |
| `$EC00` | `$F7DA` | 3035 | `SDCODE` — Rumpf von `db6502_sdbasic.s`, `CLS`, getakteter VDP-Kaltstart, allozierender Schreibpfad aus `libfat32.s` |
| `$F7DB` | `$F7FF` | 37 | frei |
| `$F800` | `$F8A1` | 162 | `SYSCALLS` |
| `$F8A2` | `$F8FF` | 94 | frei (Reserve für ein wachsendes `SYSCALLS`) |
| `$F900` | `$FEB6` | 1463 | `EXTCODE2` — `COLOR`, `SCREEN`, `PLOT`, `LINE`, `CIRCLE`, `SPRITE`, `VPOKE`, `KEY`, Text im Grafikmodus, Kalt-/Warmstart-Auswahl, Seitenlogik der Schlüsselworttabelle, siehe 5.1.1 und 5.3 |
| `$FEB7` | `$FFF9` | 323 | frei |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` |

ROM frei gesamt 1492 Bytes von 24576.

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

### 5.5 Aufgelöst: es ist eine Mikrosekunde, nicht die Adresse

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
