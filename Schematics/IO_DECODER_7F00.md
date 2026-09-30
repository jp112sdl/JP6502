# I/O-Dekodierung auf der Seite $7F00

Ersetzt die bisherige Auswahl der I/O-Bausteine im Bereich $8000–$9FFF.
Stand der Planung, noch nicht aufgebaut.

## Speicheraufteilung

```
$FFFF ┌──────────────────────────┐
      │ ROM          32 KB       │  $8000–$FFFF
$8000 ├──────────────────────────┤
      │ I/O         256 B        │  $7F00–$7FFF  8 Plätze à 32 Bytes
$7F00 ├──────────────────────────┤
      │ RAM        31,75 KB      │  $0000–$7EFF
$0000 └──────────────────────────┘
```

Die Adresse im I/O-Bereich zerfällt so:

```
         A15 A14 A13 A12 A11 A10 A9 A8 | A7 A6 A5 | A4 A3 A2 A1 A0
$7Fxx =   0   1   1   1   1   1   1  1 |   Platz  | Register im Platz
```

## Bausteine

| Baustein | Aufgabe |
|---|---|
| 74HC30 (NAND, 8 Eingänge) | erkennt A14–A8 = 1 |
| 74HC138 | wählt einen von 8 Plätzen, nur bei A15 = 0 |
| 74HC00 | ROM- und RAM-Auswahl |
| vorhandene VDP-Schaltung (74HC138 + 74HC00) | bleibt, nur mit neuer Adress-Freigabe |

## 74HC30 – Seite $7F erkennen

Pins nach üblicher Belegung, im Datenblatt prüfen.

| Pin | Signal |
|---|---|
| 1 A | A14 |
| 2 B | A13 |
| 3 C | A12 |
| 4 D | A11 |
| 5 E | A10 |
| 6 F | A9 |
| 11 G | A8 |
| 12 H | +5 V |
| 8 Y | **/P7F**, low bei $7Fxx (und bei $FFxx, dort sperrt A15 den '138) |
| 14 | +5 V |
| 7 | GND |
| 9, 10, 13 | nicht belegt |

## 74HC138 – Platz auswählen

Aktiv nur bei G1 = 1, /G2A = 0, /G2B = 0, also genau bei $7F00–$7FFF.

| Pin | Signal |
|---|---|
| 1 A | A5 |
| 2 B | A6 |
| 3 C | A7 |
| 4 /G2A | /P7F (74HC30 Pin 8) |
| 5 /G2B | A15 |
| 6 G1 | +5 V |
| 16 | +5 V |
| 8 | GND |

| Ausgang | Pin | A7 A6 A5 | Bereich | Baustein |
|---|---|---|---|---|
| /Y0 | 15 | 000 | $7F00–$7F1F | VIA1 (LCD, DS3231) |
| /Y1 | 14 | 001 | $7F20–$7F3F | VIA2 (Sound, LED, D-Pad, Lautsprecher) |
| /Y2 | 13 | 010 | $7F40–$7F5F | VIA3 (Tastatur, SD-Karte) |
| /Y3 | 12 | 011 | $7F60–$7F7F | ACIA |
| /Y4 | 11 | 100 | $7F80–$7F9F | VDP |
| /Y5 | 10 | 101 | $7FA0–$7FBF | frei, z. B. Erweiterungsport |
| /Y6 | 9 | 110 | $7FC0–$7FDF | frei |
| /Y7 | 7 | 111 | $7FE0–$7FFF | frei |

## Anschluss der Bausteine

VIA und ACIA bekommen ihr Chip-Select direkt vom '138, ohne φ2: Beide haben
einen eigenen φ2-Eingang und brauchen das Chip-Select, bevor φ2 steigt.

### W65C22 (VIA1, VIA2, VIA3)

| Pin | Signal |
|---|---|
| 23 CS2B | /Y0, /Y1 bzw. /Y2 |
| 24 CS1 | +5 V |
| 38 RS0 | A0 |
| 37 RS1 | A1 |
| 36 RS2 | A2 |
| 35 RS3 | A3 |

A4 bleibt frei: Die 16 Register erscheinen im Platz zweimal, ab +$00 und +$10.

### R6551 (ACIA)

| Pin | Signal |
|---|---|
| 3 /CS1 | /Y3 |
| 2 CS0 | +5 V |
| 13 RS0 | A0 |
| 14 RS1 | A1 |

Die 4 Register erscheinen im Platz achtmal.

### TMS9918A (VDP)

| Pin | Signal |
|---|---|
| 13 MODE | A0 (gerade: VRAM, ungerade: Register) |
| 14 /CSW, 15 /CSR | aus der vorhandenen VDP-Schaltung |

Die vorhandene Schaltung (74HC138 für R/W, 74HC00 für φ2) bleibt. Nur ihre
Adress-Freigabe, /G2A am VDP-'138 (Pin 4), kommt jetzt von /Y4.

## 74HC00 – ROM und RAM

| Gatter | Pins | Verknüpfung | Ergebnis |
|---|---|---|---|
| 1 | 1, 2 → 3 | NAND(A15, A15) | /A15 = **ROM /CE**, low bei $8000–$FFFF |
| 2 | 4, 5 → 6 | NAND(/A15, /P7F) | low bei $0000–$7EFF |
| 3 | 9, 10 → 8 | NAND(Gatter 2, Gatter 2) | invertiert: high bei RAM |
| 4 | 12, 13 → 11 | NAND(Gatter 3, φ2) | **RAM /CE**, mit φ2 verknüpft |

Pin 14 an +5 V, Pin 7 an GND, 100 nF dazwischen. φ2 ist PHI2O, Pin 39 des 65C02.
Hat das RAM heute kein φ2 im /CE, geht Gatter 2 direkt an RAM /CE, Gatter 3
und 4 bleiben frei.

Kontrolle:

| Adresse | RAM | I/O | ROM |
|---|---|---|---|
| $7EFF | an | aus | aus |
| $7F20 | aus | VIA2 | aus |
| $8000 | aus | aus | an |
| $FFFC | aus | aus | an |

## Timing (Überschlag, nicht gemessen)

Adresse steht etwa 30 ns nach der fallenden φ2-Flanke, 74HC30 und 74HC138
brauchen zusammen etwa 30–50 ns. Bei 4 MHz (125 ns φ2 low) passt das, bei
8 MHz (62,5 ns) nicht – dafür 74AHC-Bausteine.

## Nach dem Umbau prüfen

- `rom/vdp_scope` und `common/srglitch.py`: keine Störimpulse am VDP.
- Keine Software darf mehr RAM bis $7FFF beschreiben: Ein Schreibzugriff auf
  $7F61 (ACIA-Status) löst einen programmierten Reset des R6551 aus, danach
  nimmt er keine Registerzugriffe mehr an.
