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
| `$0E00` | `$0E32` | 51 | Segment `BASBUF`, Teil aus `msbasic.o`: Zustandsvariablen von `db6502_sdbasic.s` (`sd_loadmode`, `sd_savemode`, `sd_fatname`, …) |
| `$0E33` | `$0E68` | 54 | Segment `BASBUF`, Teil aus `sd.o`: Variablen des allozierenden Schreibpfads in `libfat32.s` (`fat32_partstart`, `fat32_fatsize`, `fat32_maxcluster`, `fat32_scancluster`, …) |
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
| `$F8A2` | `$FFF9` | 1880 | frei |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` — NMI `$0000`, RESET `init`, IRQ `_interrupt_handler` |

ROM frei gesamt 5212 Bytes von 24576.

### 5.1 Build `rom/microsoft_basic`

<!-- mapdoc: microsoft_basic rom -->

| Von | Bis | Bytes | Segment |
|---|---|---|---|
| `$A000` | `$A002` | 3 | `STARTUP` (`jmp init`) |
| `$A003` | `$DC0B` | 15369 | `CODE` |
| `$DC0C` | `$E307` | 1788 | `RODATA` (u. a. VDP-Zeichensatz + Registertabelle) |
| `$E308` | `$E4A8` | 417 | `BAS_VEC` / `BAS_KEY` / `BAS_ERR` |
| `$E4A9` | `$E4FF` | 87 | frei (Vorlauf bis zum Page-Alignment von `RODATA_PA`) |
| `$E500` | `$E6FF` | 512 | `RODATA_PA` (XMODEM-CRC-Tabellen, page-aligned) |
| `$E700` | `$EBE7` | 1256 | `EXTCODE` — Panel, Laufwerks-LED, Fehlertexte, FSInfo-Buchführung, `BLOCKS FREE`, Kaltstart-Leuchte, `SOUND` |
| `$EBE8` | `$EBFF` | 24 | frei |
| `$EC00` | `$F7F3` | 3060 | `SDCODE` — Rumpf von `db6502_sdbasic.s`, `CLS`, `COLOR`, getakteter VDP-Kaltstart, allozierender Schreibpfad aus `libfat32.s` |
| `$F7F4` | `$F7FF` | 12 | frei |
| `$F800` | `$F8A1` | 162 | `SYSCALLS` |
| `$F8A2` | `$FFF9` | 1880 | frei — auf dieser Platine noch nie belegt, siehe 5.2.1 |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` |

ROM frei gesamt 2003 Bytes von 24576.

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
Block unterzubringen waren. Damit ist Schluss: der nächste Befehl braucht
`$F8A2`–`$FFF9`. Frei ist danach nur noch `$F8A2`–`$FFF9` — ein Bereich, der
auf dieser Platine noch nie belegt war. Bei `EXTCODE` (Abschnitt 5.2, Ende)
ließ sich das nur durch Benutzen herausfinden; für einen neuen Block dort gilt
dasselbe, also bewusst mit einer kleinen, gut sichtbaren Funktion anfangen.

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
