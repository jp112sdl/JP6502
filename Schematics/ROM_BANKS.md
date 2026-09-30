# ROM-Bänke per DIP-Schalter

Der W29C020 fasst 256 KB, die CPU sieht davon 32 KB (`$8000`–`$FFFF`, die
ersten 8 KB verdeckt das I/O). Legt man die drei oberen Adressleitungen des
Flash an Schalter statt fest auf GND, stehen acht Images zu je 32 KB zur Wahl:
Schalter umstellen, Reset, und die CPU startet aus der gewählten Bank.

## Belegung

| Bank | S3 (A17) | S2 (A16) | S1 (A15) | Offset im Flash | Firmware | Datei |
|---|---|---|---|---|---|---|
| 0 | aus | aus | aus | `0x00000` | MS-BASIC | `Software/build/rom/microsoft_basic.ext.bin` |
| 1 | aus | aus | an | `0x08000` | GeckOS | `GeckOS-V2/arch/jp6502/boot/geckos.bin` |
| 2 | aus | an | aus | `0x10000` | minimal_bootloader | `Software/build/rom/minimal_bootloader.ext.bin` |
| 3 | aus | an | an | `0x18000` | frei | |
| 4–7 | an | … | … | `0x20000`–`0x38000` | frei | |

Alle Schalter aus ist Bank 0: Das ist auch das, was ohne Schalter bisher im
Flash bei Offset 0 stand.

## Schaltung

Die drei Pins des Flash, die heute vermutlich fest an GND liegen, bekommen je
einen Pull-down und einen Schalter nach +5 V:

```
           +5 V
            │
           S1 ─ DIP-Schalter
            │
Flash A15 ──┴──[10k]── GND        (ebenso A16 mit S2, A17 mit S3)
```

| Flash-Pin (DIP-32) | Signal | Schalter |
|---|---|---|
| 3 | A15 | S1 |
| 2 | A16 | S2 |
| 30 | A17 | S3 |

Pins nach der üblichen JEDEC-Belegung für 32-polige Flash-Bausteine, im
Datenblatt des W29C020 prüfen (im PLCC-Gehäuse liegen sie anders). Vorher
nachsehen, woran die drei Pins heute hängen - liegen sie nicht an GND, stand
das bisherige Image in einer anderen Bank.

- Für drei Firmwares reichen S1 und S2. A17 kann an GND bleiben, oder gleich
  mit Schalter, dann sind es acht Bänke.
- 10 kΩ halten die Leitungen bei offenem Schalter sicher auf Low; die
  Eingänge des Flash sind CMOS und ziehen praktisch keinen Strom.
- `/WE` des Flash bleibt wie gehabt fest auf High.

**Nur bei Reset oder ausgeschaltet umschalten.** Die CPU liest die neue Bank
sofort; wer während des Betriebs schaltet, lässt sie mitten im Programm im
anderen Image weiterlaufen. Also: umschalten, dann Reset.

## Flashen

Jedes Image ist wie bisher 32 KB groß und kommt an den Offset seiner Bank.
Die anderen Bänke dürfen dabei nicht gelöscht werden:

```
python3 FlashPROMv2/tools/flashtool.py write Software/build/rom/microsoft_basic.ext.bin --offset 0x00000 --erase none
python3 FlashPROMv2/tools/flashtool.py write GeckOS-V2/arch/jp6502/boot/geckos.bin --offset 0x08000 --erase none
python3 FlashPROMv2/tools/flashtool.py write Software/build/rom/minimal_bootloader.ext.bin --offset 0x10000 --erase none
```

- **`--erase none` ist Pflicht.** Ohne Angabe löscht `flashtool.py` den
  W29C020 vorher ganz - und damit alle anderen Bänke.
- Das geht beim W29C020, weil er beim Schreiben einer 128-Byte-Seite diese
  Seite selbst löscht. Ein Flash, das byteweise programmiert wird (etwa
  SST39SF020A), braucht stattdessen `--erase sectors`.
- In JP6502Control wählt man im Flash-Tab die Bank; Offset und
  „Do not erase" stellt der Tab dann selbst ein.
