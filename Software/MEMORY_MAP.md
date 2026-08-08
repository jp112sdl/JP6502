# DB6502 / wooandy — Memory Map

Stand: 2026-08-08. Abgeleitet aus `common/firmware.ext.cfg`, `common/load.cfg`
und den ld65-Mapfiles des vollständigen Builds (cc65 V2.19).
Referenz-Build: `rom/os1` mit `ADDRESS_MODE=ext` (Default).
Alle Pfadangaben sind relativ zu `Software/`.

---

## 1. Gesamtsystem (64K Adressraum)

| Bereich | Von | Bis | Größe | Inhalt |
|---|---|---|---|---|
| ZP | `$0000` | `$00FF` | 256 | Zero Page |
| STACK | `$0100` | `$01FF` | 256 | 6502 Hardware-Stack |
| SYS_RAM | `$0200` | `$0BFF` | 2560 | Firmware-RAM (`SYSRAM` + `BSS`) |
| FAT_RAM | `$0C00` | `$0DFF` | 512 | `FATBUF` — FAT32-Sektor-Workspace, page-aligned |
| BAS_RAM | `$0E00` | `$0EFF` | 256 | MS-BASIC `INPUTBUFFER`, page-aligned |
| *(Reserve)* | `$0F00` | `$0FFF` | 256 | frei |
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
| `$0000` | `$004C` | 77 | `common/source/zeropage.s` | cc65-Runtime (`c_sp`,`sreg`,`regsave`,`ptr1..4`,`tmp1..4`) + System-Variablen |
| `$004D` | `$0053` | 7 | `common/source/modem.s` | `crc`,`block_number`,`first_block_flag`,`memory_pointer`,`delay_counter` |
| `$0054` | `$0055` | 2 | `common/source/sd.s` | `memory_pointer` (2. Instanz) |
| `$0056` | `$00FF` | **170** | — | **frei** |

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
| `$35` | 24 | `zp_fat32_variables` |

Bei MS-BASIC (`rom/microsoft_basic`) belegt `basic_zp.s` zusätzlich `$004D`–`$00BD`;
ZP-Ende dort `$00C6`, frei `$00C7`–`$00FF` (57 Bytes).

---

## 3. SYS_RAM — `$0200`–`$0EFF`

### 3.1 Segment `SYSRAM` (`common/source/sysram_map.s`), `$0200`–`$0813`

| Von | Bis | Bytes | Symbol |
|---|---|---|---|
| `$0200` | `$02FF` | 256 | `acia_rx_buffer` |
| `$0300` | `$03FF` | 256 | `acia_tx_buffer` |
| `$0400` | `$043F` | 64 | `keyboard_buffer` |
| `$0440` | `$0453` | 20 | `lcd_line_buffer` |
| `$0454` | `$0813` | 960 | `text_screen_buffer` (VDP 40×24) |

### 3.2 Segment `BSS` (Build `rom/os1`), `$0814`–`$09AC`

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

| `$09AD` | `$0BFF` | **595** | **frei** (Reserve für wachsendes BSS) |

BSS bei `rom/microsoft_basic`: `$0814`–`$092C` (281 Bytes).

### 3.3 `FAT_RAM` — `$0C00`–`$0DFF`

Segment `FATBUF`, definiert in `common/source/sd.s`. Enthält `fat32_workspace` (512 Bytes,
page-aligned) = `fat32_readbuffer` aus `libfat32.s`. Nur belegt, wenn `sd.o` gelinkt wird.

### 3.4 `BAS_RAM` — `$0E00`–`$0EFF`

`INPUTBUFFER` von MS-BASIC. Bleibt eine Assemblierzeit-Konstante in `defines_db6502.s`
(`defines.s` wertet sie in `.if` aus und bildet `INPUTBUFFERX = INPUTBUFFER & $FF00`);
die Übereinstimmung mit der Memory-Area wird per `.assert` gegen `__BAS_RAM_START__`
zur Linkzeit geprüft.

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

| Von | Bis | Bytes | Segment |
|---|---|---|---|
| `$A000` | `$CA85` | 10886 | `CODE` |
| `$CA86` | `$DD3F` | 4794 | `RODATA` |
| `$DE00` | `$DFFF` | 512 | `RODATA_PA` (XMODEM-CRC-Tabellen, page-aligned) |
| `$E000` | `$F7FF` | 6144 | frei |
| `$F800` | `$F8A1` | 162 | `SYSCALLS` (feste Sprungtabelle für Loadables) |
| `$F8A2` | `$FFF9` | 1880 | frei |
| `$FFFA` | `$FFFF` | 6 | `VECTORS` — NMI `$0000`, RESET `init`, IRQ `_interrupt_handler` |

ROM frei gesamt ≈ 8 KB von 24 KB.
`rom/microsoft_basic`: `CODE` `$A000`–`$D9CF`, `RODATA` bis `$E0F6`, `BAS_VEC/KEY/ERR` `$E0F7`–`$E283`,
`RODATA_PA` `$E300`–`$E4FF`, frei `$E500`–`$F7FF`.

---

## 6. Kollisionen — Status

Behoben in Phase 1 (Build `rom/microsoft_basic`, verifiziert gegen die Mapfiles):

| # | Ehemals | Jetzt |
|---|---|---|
| 1 | `sd.s: fat32_workspace = $0200` über `acia_rx_buffer`/`acia_tx_buffer` | Segment `FATBUF` → `$0C00` |
| 2 | `sd.s: buffer = $0400` über `keyboard_buffer`/`lcd_line_buffer`/`text_screen_buffer` | `buffer = __USERRAM_START__` (`$1000`) |
| 3 | `INPUTBUFFER = $0900` im `BSS` | `$0E00` in `BAS_RAM`, per `.assert` abgesichert |
| 4 | MS-BASIC RAM-Probe ohne Obergrenze → schreibt in VDP/VIA/ACIA | `.ifdef DB6502` Limit `$8000` in `init.s` |
| 5 | XMODEM-Empfang ohne Bereichsprüfung | Ladeadresse und Fortschritt auf `$1000`–`$7FFF` begrenzt |
| — | `SYS_RAM` reichte bis `$0EFF`, Überlauf blieb unbemerkt | `SYS_RAM` endet `$0BFF`, Überlauf ist jetzt ein ld65-Fehler |

Offen (bewusst zurückgestellt, Loadable-Builds außerhalb des Scope):

| # | Bereich | Kollidiert mit |
|---|---|---|
| 7 | `load/22_msbasic/defines_db6502.s: INPUTBUFFER = $0900` | Firmware-`BSS` |
| 8 | `db6502_extra.s: TXTBUFFER` in Segment `SYSRAM` (64 B, ab `$0814`) | Firmware-`BSS` bei Loadable-Build |
| 9 | `load.cfg: USERRAM $30FF+$5000` → Ende `$80FE` | VDP `$8080` |
| 10 | `firmware.basic.cfg` — wird in Phase 2 gelöscht | — |
