; KrisOS Sound Library
;
; Copyright 2020 Kris Foster
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.

; .ifndef _SOUND_H_
; _SOUND_H_ = 1


; Data formats
; LCCTDDDD
; Latch indicator
; Channel
; Register type (0=tone, 1=volume)
; Data
; 1CCTDDDD (latch byte)
; 0-DDDDDD (data byte)
FIRST           = %10000000
SECOND          = %00000000
CHANNEL_1       = %00000000
CHANNEL_2       = %00100000
CHANNEL_3       = %01000000
CHANNEL_NOISE   = %01100000
TONE            = %00000000
VOLUME          = %00010000
VOLUME_OFF      = %00001111
VOLUME_MAX      = %00000000
SN_READY        = %00000001 ; Ready pin
SN_WE           = %00000010 ; Write enable pin (active low)
SN_WE_CLEAR     = %00000000
SN_CE           = %00000100 ; Chip enable pin (active low) - Tied to ground
SN_DATA         = %11111111 ; Data pins
LED_ON          = %10000000 ; LED pin ON
LED_OFF         = %00000000 ; LED pin OFF
D_PAD           = %00000000 ; D-Pad

; Notes
; Note, (s)harp/(f)lat/(n)atural, octave, byte 1 or 2
;
; The SN76489 plays clock / (32 * divider), the divider has ten bits. The
; chip runs on the CPU oscillator, so the dividers are worked out here from
; the frequency of each note (equal temperament, A4 = 440 Hz) and the clock
; the ROM is built for, rounded to the nearest. A note whose divider does
; not fit in ten bits comes out as 0 - at 4 MHz everything below B2.
; Byte 1 is the low four bits of the divider, for the latch byte, byte 2 the
; upper six.

        .include "clock.inc"

.if clock_mhz = 0
SN_CLOCK = 2000000              ; slow and 250k: what the table used to be
.else
SN_CLOCK = clock_mhz * 1000000
.endif
SN_CLOCK_100 = SN_CLOCK / 32 * 100      ; clock / 32 in hundredths of a Hz

; For each note: the divider (_d), for a frequency in hundredths of a Hz,
; then its two parts, 0 when the divider does not fit.

Cn0_d = (SN_CLOCK_100 + 817) / 1635 ; 12 C0, 16.35 Hz
Cn0_1 = (Cn0_d & $0F) * (Cn0_d < 1024)
Cn0_2 = (Cn0_d >> 4) * (Cn0_d < 1024)
Cs0_d = (SN_CLOCK_100 + 866) / 1732 ; 13 C#0/Db0, 17.32 Hz
Cs0_1 = (Cs0_d & $0F) * (Cs0_d < 1024)
Cs0_2 = (Cs0_d >> 4) * (Cs0_d < 1024)
Dn0_d = (SN_CLOCK_100 + 917) / 1835 ; 14 D0, 18.35 Hz
Dn0_1 = (Dn0_d & $0F) * (Dn0_d < 1024)
Dn0_2 = (Dn0_d >> 4) * (Dn0_d < 1024)
Ds0_d = (SN_CLOCK_100 + 972) / 1945 ; 15 D#0/Eb0, 19.45 Hz
Ds0_1 = (Ds0_d & $0F) * (Ds0_d < 1024)
Ds0_2 = (Ds0_d >> 4) * (Ds0_d < 1024)
En0_d = (SN_CLOCK_100 + 1030) / 2060 ; 16 E0, 20.60 Hz
En0_1 = (En0_d & $0F) * (En0_d < 1024)
En0_2 = (En0_d >> 4) * (En0_d < 1024)
Fn0_d = (SN_CLOCK_100 + 1091) / 2183 ; 17 F0, 21.83 Hz
Fn0_1 = (Fn0_d & $0F) * (Fn0_d < 1024)
Fn0_2 = (Fn0_d >> 4) * (Fn0_d < 1024)
Fs0_d = (SN_CLOCK_100 + 1156) / 2312 ; 18 F#0/Gb0, 23.12 Hz
Fs0_1 = (Fs0_d & $0F) * (Fs0_d < 1024)
Fs0_2 = (Fs0_d >> 4) * (Fs0_d < 1024)
Gn0_d = (SN_CLOCK_100 + 1225) / 2450 ; 19 G0, 24.50 Hz
Gn0_1 = (Gn0_d & $0F) * (Gn0_d < 1024)
Gn0_2 = (Gn0_d >> 4) * (Gn0_d < 1024)
Gs0_d = (SN_CLOCK_100 + 1298) / 2596 ; 20 G#0/Ab0, 25.96 Hz
Gs0_1 = (Gs0_d & $0F) * (Gs0_d < 1024)
Gs0_2 = (Gs0_d >> 4) * (Gs0_d < 1024)
An0_d = (SN_CLOCK_100 + 1375) / 2750 ; 21 A0, 27.50 Hz
An0_1 = (An0_d & $0F) * (An0_d < 1024)
An0_2 = (An0_d >> 4) * (An0_d < 1024)
As0_d = (SN_CLOCK_100 + 1457) / 2914 ; 22 A#0/Bb0, 29.14 Hz
As0_1 = (As0_d & $0F) * (As0_d < 1024)
As0_2 = (As0_d >> 4) * (As0_d < 1024)
Bn0_d = (SN_CLOCK_100 + 1543) / 3087 ; 23 B0, 30.87 Hz
Bn0_1 = (Bn0_d & $0F) * (Bn0_d < 1024)
Bn0_2 = (Bn0_d >> 4) * (Bn0_d < 1024)
Cn1_d = (SN_CLOCK_100 + 1635) / 3270 ; 24 C1, 32.70 Hz
Cn1_1 = (Cn1_d & $0F) * (Cn1_d < 1024)
Cn1_2 = (Cn1_d >> 4) * (Cn1_d < 1024)
Cs1_d = (SN_CLOCK_100 + 1732) / 3465 ; 25 C#1/Db1, 34.65 Hz
Cs1_1 = (Cs1_d & $0F) * (Cs1_d < 1024)
Cs1_2 = (Cs1_d >> 4) * (Cs1_d < 1024)
Dn1_d = (SN_CLOCK_100 + 1835) / 3671 ; 26 D1, 36.71 Hz
Dn1_1 = (Dn1_d & $0F) * (Dn1_d < 1024)
Dn1_2 = (Dn1_d >> 4) * (Dn1_d < 1024)
Ds1_d = (SN_CLOCK_100 + 1944) / 3889 ; 27 D#1/Eb1, 38.89 Hz
Ds1_1 = (Ds1_d & $0F) * (Ds1_d < 1024)
Ds1_2 = (Ds1_d >> 4) * (Ds1_d < 1024)
En1_d = (SN_CLOCK_100 + 2060) / 4120 ; 28 E1, 41.20 Hz
En1_1 = (En1_d & $0F) * (En1_d < 1024)
En1_2 = (En1_d >> 4) * (En1_d < 1024)
Fn1_d = (SN_CLOCK_100 + 2182) / 4365 ; 29 F1, 43.65 Hz
Fn1_1 = (Fn1_d & $0F) * (Fn1_d < 1024)
Fn1_2 = (Fn1_d >> 4) * (Fn1_d < 1024)
Fs1_d = (SN_CLOCK_100 + 2312) / 4625 ; 30 F#1/Gb1, 46.25 Hz
Fs1_1 = (Fs1_d & $0F) * (Fs1_d < 1024)
Fs1_2 = (Fs1_d >> 4) * (Fs1_d < 1024)
Gn1_d = (SN_CLOCK_100 + 2450) / 4900 ; 31 G1, 49.00 Hz
Gn1_1 = (Gn1_d & $0F) * (Gn1_d < 1024)
Gn1_2 = (Gn1_d >> 4) * (Gn1_d < 1024)
Gs1_d = (SN_CLOCK_100 + 2595) / 5191 ; 32 G#1/Ab1, 51.91 Hz
Gs1_1 = (Gs1_d & $0F) * (Gs1_d < 1024)
Gs1_2 = (Gs1_d >> 4) * (Gs1_d < 1024)
An1_d = (SN_CLOCK_100 + 2750) / 5500 ; 33 A1, 55.00 Hz
An1_1 = (An1_d & $0F) * (An1_d < 1024)
An1_2 = (An1_d >> 4) * (An1_d < 1024)
As1_d = (SN_CLOCK_100 + 2913) / 5827 ; 34 A#1/Bb1, 58.27 Hz
As1_1 = (As1_d & $0F) * (As1_d < 1024)
As1_2 = (As1_d >> 4) * (As1_d < 1024)
Bn1_d = (SN_CLOCK_100 + 3087) / 6174 ; 35 B1, 61.74 Hz
Bn1_1 = (Bn1_d & $0F) * (Bn1_d < 1024)
Bn1_2 = (Bn1_d >> 4) * (Bn1_d < 1024)
Cn2_d = (SN_CLOCK_100 + 3270) / 6541 ; 36 C2, 65.41 Hz
Cn2_1 = (Cn2_d & $0F) * (Cn2_d < 1024)
Cn2_2 = (Cn2_d >> 4) * (Cn2_d < 1024)
Cs2_d = (SN_CLOCK_100 + 3465) / 6930 ; 37 C#2/Db2, 69.30 Hz
Cs2_1 = (Cs2_d & $0F) * (Cs2_d < 1024)
Cs2_2 = (Cs2_d >> 4) * (Cs2_d < 1024)
Dn2_d = (SN_CLOCK_100 + 3671) / 7342 ; 38 D2, 73.42 Hz
Dn2_1 = (Dn2_d & $0F) * (Dn2_d < 1024)
Dn2_2 = (Dn2_d >> 4) * (Dn2_d < 1024)
Ds2_d = (SN_CLOCK_100 + 3889) / 7778 ; 39 D#2/Eb2, 77.78 Hz
Ds2_1 = (Ds2_d & $0F) * (Ds2_d < 1024)
Ds2_2 = (Ds2_d >> 4) * (Ds2_d < 1024)
En2_d = (SN_CLOCK_100 + 4120) / 8241 ; 40 E2, 82.41 Hz
En2_1 = (En2_d & $0F) * (En2_d < 1024)
En2_2 = (En2_d >> 4) * (En2_d < 1024)
Fn2_d = (SN_CLOCK_100 + 4365) / 8731 ; 41 F2, 87.31 Hz
Fn2_1 = (Fn2_d & $0F) * (Fn2_d < 1024)
Fn2_2 = (Fn2_d >> 4) * (Fn2_d < 1024)
Fs2_d = (SN_CLOCK_100 + 4625) / 9250 ; 42 F#2/Gb2, 92.50 Hz
Fs2_1 = (Fs2_d & $0F) * (Fs2_d < 1024)
Fs2_2 = (Fs2_d >> 4) * (Fs2_d < 1024)
Gn2_d = (SN_CLOCK_100 + 4900) / 9800 ; 43 G2, 98.00 Hz
Gn2_1 = (Gn2_d & $0F) * (Gn2_d < 1024)
Gn2_2 = (Gn2_d >> 4) * (Gn2_d < 1024)
Gs2_d = (SN_CLOCK_100 + 5191) / 10383 ; 44 G#2/Ab2, 103.83 Hz
Gs2_1 = (Gs2_d & $0F) * (Gs2_d < 1024)
Gs2_2 = (Gs2_d >> 4) * (Gs2_d < 1024)
An2_d = (SN_CLOCK_100 + 5500) / 11000 ; 45 A2, 110.00 Hz
An2_1 = (An2_d & $0F) * (An2_d < 1024)
An2_2 = (An2_d >> 4) * (An2_d < 1024)
As2_d = (SN_CLOCK_100 + 5827) / 11654 ; 46 A#2/Bb2, 116.54 Hz
As2_1 = (As2_d & $0F) * (As2_d < 1024)
As2_2 = (As2_d >> 4) * (As2_d < 1024)
Bn2_d = (SN_CLOCK_100 + 6173) / 12347 ; 47 B2, 123.47 Hz
Bn2_1 = (Bn2_d & $0F) * (Bn2_d < 1024)
Bn2_2 = (Bn2_d >> 4) * (Bn2_d < 1024)
Cn3_d = (SN_CLOCK_100 + 6540) / 13081 ; 48 C3, 130.81 Hz
Cn3_1 = (Cn3_d & $0F) * (Cn3_d < 1024)
Cn3_2 = (Cn3_d >> 4) * (Cn3_d < 1024)
Cs3_d = (SN_CLOCK_100 + 6929) / 13859 ; 49 C#3/Db3, 138.59 Hz
Cs3_1 = (Cs3_d & $0F) * (Cs3_d < 1024)
Cs3_2 = (Cs3_d >> 4) * (Cs3_d < 1024)
Dn3_d = (SN_CLOCK_100 + 7341) / 14683 ; 50 D3, 146.83 Hz
Dn3_1 = (Dn3_d & $0F) * (Dn3_d < 1024)
Dn3_2 = (Dn3_d >> 4) * (Dn3_d < 1024)
Ds3_d = (SN_CLOCK_100 + 7778) / 15556 ; 51 D#3/Eb3, 155.56 Hz
Ds3_1 = (Ds3_d & $0F) * (Ds3_d < 1024)
Ds3_2 = (Ds3_d >> 4) * (Ds3_d < 1024)
En3_d = (SN_CLOCK_100 + 8240) / 16481 ; 52 E3, 164.81 Hz
En3_1 = (En3_d & $0F) * (En3_d < 1024)
En3_2 = (En3_d >> 4) * (En3_d < 1024)
Fn3_d = (SN_CLOCK_100 + 8730) / 17461 ; 53 F3, 174.61 Hz
Fn3_1 = (Fn3_d & $0F) * (Fn3_d < 1024)
Fn3_2 = (Fn3_d >> 4) * (Fn3_d < 1024)
Fs3_d = (SN_CLOCK_100 + 9250) / 18500 ; 54 F#3/Gb3, 185.00 Hz
Fs3_1 = (Fs3_d & $0F) * (Fs3_d < 1024)
Fs3_2 = (Fs3_d >> 4) * (Fs3_d < 1024)
Gn3_d = (SN_CLOCK_100 + 9800) / 19600 ; 55 G3, 196.00 Hz
Gn3_1 = (Gn3_d & $0F) * (Gn3_d < 1024)
Gn3_2 = (Gn3_d >> 4) * (Gn3_d < 1024)
Gs3_d = (SN_CLOCK_100 + 10382) / 20765 ; 56 G#3/Ab3, 207.65 Hz
Gs3_1 = (Gs3_d & $0F) * (Gs3_d < 1024)
Gs3_2 = (Gs3_d >> 4) * (Gs3_d < 1024)
An3_d = (SN_CLOCK_100 + 11000) / 22000 ; 57 A3, 220.00 Hz
An3_1 = (An3_d & $0F) * (An3_d < 1024)
An3_2 = (An3_d >> 4) * (An3_d < 1024)
As3_d = (SN_CLOCK_100 + 11654) / 23308 ; 58 A#3/Bb3, 233.08 Hz
As3_1 = (As3_d & $0F) * (As3_d < 1024)
As3_2 = (As3_d >> 4) * (As3_d < 1024)
Bn3_d = (SN_CLOCK_100 + 12347) / 24694 ; 59 B3, 246.94 Hz
Bn3_1 = (Bn3_d & $0F) * (Bn3_d < 1024)
Bn3_2 = (Bn3_d >> 4) * (Bn3_d < 1024)
Cn4_d = (SN_CLOCK_100 + 13081) / 26163 ; 60 C4, 261.63 Hz
Cn4_1 = (Cn4_d & $0F) * (Cn4_d < 1024)
Cn4_2 = (Cn4_d >> 4) * (Cn4_d < 1024)
Cs4_d = (SN_CLOCK_100 + 13859) / 27718 ; 61 C#4/Db4, 277.18 Hz
Cs4_1 = (Cs4_d & $0F) * (Cs4_d < 1024)
Cs4_2 = (Cs4_d >> 4) * (Cs4_d < 1024)
Dn4_d = (SN_CLOCK_100 + 14683) / 29366 ; 62 D4, 293.66 Hz
Dn4_1 = (Dn4_d & $0F) * (Dn4_d < 1024)
Dn4_2 = (Dn4_d >> 4) * (Dn4_d < 1024)
Ds4_d = (SN_CLOCK_100 + 15556) / 31113 ; 63 D#4/Eb4, 311.13 Hz
Ds4_1 = (Ds4_d & $0F) * (Ds4_d < 1024)
Ds4_2 = (Ds4_d >> 4) * (Ds4_d < 1024)
En4_d = (SN_CLOCK_100 + 16481) / 32963 ; 64 E4, 329.63 Hz
En4_1 = (En4_d & $0F) * (En4_d < 1024)
En4_2 = (En4_d >> 4) * (En4_d < 1024)
Fn4_d = (SN_CLOCK_100 + 17461) / 34923 ; 65 F4, 349.23 Hz
Fn4_1 = (Fn4_d & $0F) * (Fn4_d < 1024)
Fn4_2 = (Fn4_d >> 4) * (Fn4_d < 1024)
Fs4_d = (SN_CLOCK_100 + 18499) / 36999 ; 66 F#4/Gb4, 369.99 Hz
Fs4_1 = (Fs4_d & $0F) * (Fs4_d < 1024)
Fs4_2 = (Fs4_d >> 4) * (Fs4_d < 1024)
Gn4_d = (SN_CLOCK_100 + 19600) / 39200 ; 67 G4, 392.00 Hz
Gn4_1 = (Gn4_d & $0F) * (Gn4_d < 1024)
Gn4_2 = (Gn4_d >> 4) * (Gn4_d < 1024)
Gs4_d = (SN_CLOCK_100 + 20765) / 41530 ; 68 G#4/Ab4, 415.30 Hz
Gs4_1 = (Gs4_d & $0F) * (Gs4_d < 1024)
Gs4_2 = (Gs4_d >> 4) * (Gs4_d < 1024)
An4_d = (SN_CLOCK_100 + 22000) / 44000 ; 69 A4, 440.00 Hz
An4_1 = (An4_d & $0F) * (An4_d < 1024)
An4_2 = (An4_d >> 4) * (An4_d < 1024)
As4_d = (SN_CLOCK_100 + 23308) / 46616 ; 70 A#4/Bb4, 466.16 Hz
As4_1 = (As4_d & $0F) * (As4_d < 1024)
As4_2 = (As4_d >> 4) * (As4_d < 1024)
Bn4_d = (SN_CLOCK_100 + 24694) / 49388 ; 71 B4, 493.88 Hz
Bn4_1 = (Bn4_d & $0F) * (Bn4_d < 1024)
Bn4_2 = (Bn4_d >> 4) * (Bn4_d < 1024)
Cn5_d = (SN_CLOCK_100 + 26162) / 52325 ; 72 C5, 523.25 Hz
Cn5_1 = (Cn5_d & $0F) * (Cn5_d < 1024)
Cn5_2 = (Cn5_d >> 4) * (Cn5_d < 1024)
Cs5_d = (SN_CLOCK_100 + 27718) / 55437 ; 73 C#5/Db5, 554.37 Hz
Cs5_1 = (Cs5_d & $0F) * (Cs5_d < 1024)
Cs5_2 = (Cs5_d >> 4) * (Cs5_d < 1024)
Dn5_d = (SN_CLOCK_100 + 29366) / 58733 ; 74 D5, 587.33 Hz
Dn5_1 = (Dn5_d & $0F) * (Dn5_d < 1024)
Dn5_2 = (Dn5_d >> 4) * (Dn5_d < 1024)
Ds5_d = (SN_CLOCK_100 + 31112) / 62225 ; 75 D#5/Eb5, 622.25 Hz
Ds5_1 = (Ds5_d & $0F) * (Ds5_d < 1024)
Ds5_2 = (Ds5_d >> 4) * (Ds5_d < 1024)
En5_d = (SN_CLOCK_100 + 32963) / 65926 ; 76 E5, 659.26 Hz
En5_1 = (En5_d & $0F) * (En5_d < 1024)
En5_2 = (En5_d >> 4) * (En5_d < 1024)
Fn5_d = (SN_CLOCK_100 + 34923) / 69846 ; 77 F5, 698.46 Hz
Fn5_1 = (Fn5_d & $0F) * (Fn5_d < 1024)
Fn5_2 = (Fn5_d >> 4) * (Fn5_d < 1024)
Fs5_d = (SN_CLOCK_100 + 36999) / 73999 ; 78 F#5/Gb5, 739.99 Hz
Fs5_1 = (Fs5_d & $0F) * (Fs5_d < 1024)
Fs5_2 = (Fs5_d >> 4) * (Fs5_d < 1024)
Gn5_d = (SN_CLOCK_100 + 39199) / 78399 ; 79 G5, 783.99 Hz
Gn5_1 = (Gn5_d & $0F) * (Gn5_d < 1024)
Gn5_2 = (Gn5_d >> 4) * (Gn5_d < 1024)
Gs5_d = (SN_CLOCK_100 + 41530) / 83061 ; 80 G#5/Ab5, 830.61 Hz
Gs5_1 = (Gs5_d & $0F) * (Gs5_d < 1024)
Gs5_2 = (Gs5_d >> 4) * (Gs5_d < 1024)
An5_d = (SN_CLOCK_100 + 44000) / 88000 ; 81 A5, 880.00 Hz
An5_1 = (An5_d & $0F) * (An5_d < 1024)
An5_2 = (An5_d >> 4) * (An5_d < 1024)
As5_d = (SN_CLOCK_100 + 46616) / 93233 ; 82 A#5/Bb5, 932.33 Hz
As5_1 = (As5_d & $0F) * (As5_d < 1024)
As5_2 = (As5_d >> 4) * (As5_d < 1024)
Bn5_d = (SN_CLOCK_100 + 49388) / 98777 ; 83 B5, 987.77 Hz
Bn5_1 = (Bn5_d & $0F) * (Bn5_d < 1024)
Bn5_2 = (Bn5_d >> 4) * (Bn5_d < 1024)
Cn6_d = (SN_CLOCK_100 + 52325) / 104650 ; 84 C6, 1046.50 Hz
Cn6_1 = (Cn6_d & $0F) * (Cn6_d < 1024)
Cn6_2 = (Cn6_d >> 4) * (Cn6_d < 1024)
Cs6_d = (SN_CLOCK_100 + 55436) / 110873 ; 85 C#6/Db6, 1108.73 Hz
Cs6_1 = (Cs6_d & $0F) * (Cs6_d < 1024)
Cs6_2 = (Cs6_d >> 4) * (Cs6_d < 1024)
Dn6_d = (SN_CLOCK_100 + 58733) / 117466 ; 86 D6, 1174.66 Hz
Dn6_1 = (Dn6_d & $0F) * (Dn6_d < 1024)
Dn6_2 = (Dn6_d >> 4) * (Dn6_d < 1024)
Ds6_d = (SN_CLOCK_100 + 62225) / 124451 ; 87 D#6/Eb6, 1244.51 Hz
Ds6_1 = (Ds6_d & $0F) * (Ds6_d < 1024)
Ds6_2 = (Ds6_d >> 4) * (Ds6_d < 1024)
En6_d = (SN_CLOCK_100 + 65925) / 131851 ; 88 E6, 1318.51 Hz
En6_1 = (En6_d & $0F) * (En6_d < 1024)
En6_2 = (En6_d >> 4) * (En6_d < 1024)
Fn6_d = (SN_CLOCK_100 + 69845) / 139691 ; 89 F6, 1396.91 Hz
Fn6_1 = (Fn6_d & $0F) * (Fn6_d < 1024)
Fn6_2 = (Fn6_d >> 4) * (Fn6_d < 1024)
Fs6_d = (SN_CLOCK_100 + 73999) / 147998 ; 90 F#6/Gb6, 1479.98 Hz
Fs6_1 = (Fs6_d & $0F) * (Fs6_d < 1024)
Fs6_2 = (Fs6_d >> 4) * (Fs6_d < 1024)
Gn6_d = (SN_CLOCK_100 + 78399) / 156798 ; 91 G6, 1567.98 Hz
Gn6_1 = (Gn6_d & $0F) * (Gn6_d < 1024)
Gn6_2 = (Gn6_d >> 4) * (Gn6_d < 1024)
Gs6_d = (SN_CLOCK_100 + 83061) / 166122 ; 92 G#6/Ab6, 1661.22 Hz
Gs6_1 = (Gs6_d & $0F) * (Gs6_d < 1024)
Gs6_2 = (Gs6_d >> 4) * (Gs6_d < 1024)
An6_d = (SN_CLOCK_100 + 88000) / 176000 ; 93 A6, 1760.00 Hz
An6_1 = (An6_d & $0F) * (An6_d < 1024)
An6_2 = (An6_d >> 4) * (An6_d < 1024)
As6_d = (SN_CLOCK_100 + 93233) / 186466 ; 94 A#6/Bb6, 1864.66 Hz
As6_1 = (As6_d & $0F) * (As6_d < 1024)
As6_2 = (As6_d >> 4) * (As6_d < 1024)
Bn6_d = (SN_CLOCK_100 + 98776) / 197553 ; 95 B6, 1975.53 Hz
Bn6_1 = (Bn6_d & $0F) * (Bn6_d < 1024)
Bn6_2 = (Bn6_d >> 4) * (Bn6_d < 1024)
Cn7_d = (SN_CLOCK_100 + 104650) / 209300 ; 96 C7, 2093.00 Hz
Cn7_1 = (Cn7_d & $0F) * (Cn7_d < 1024)
Cn7_2 = (Cn7_d >> 4) * (Cn7_d < 1024)
Cs7_d = (SN_CLOCK_100 + 110873) / 221746 ; 97 C#7/Db7, 2217.46 Hz
Cs7_1 = (Cs7_d & $0F) * (Cs7_d < 1024)
Cs7_2 = (Cs7_d >> 4) * (Cs7_d < 1024)
Dn7_d = (SN_CLOCK_100 + 117466) / 234932 ; 98 D7, 2349.32 Hz
Dn7_1 = (Dn7_d & $0F) * (Dn7_d < 1024)
Dn7_2 = (Dn7_d >> 4) * (Dn7_d < 1024)
Ds7_d = (SN_CLOCK_100 + 124451) / 248902 ; 99 D#7/Eb7, 2489.02 Hz
Ds7_1 = (Ds7_d & $0F) * (Ds7_d < 1024)
Ds7_2 = (Ds7_d >> 4) * (Ds7_d < 1024)
En7_d = (SN_CLOCK_100 + 131851) / 263702 ; 100 E7, 2637.02 Hz
En7_1 = (En7_d & $0F) * (En7_d < 1024)
En7_2 = (En7_d >> 4) * (En7_d < 1024)
Fn7_d = (SN_CLOCK_100 + 139691) / 279383 ; 101 F7, 2793.83 Hz
Fn7_1 = (Fn7_d & $0F) * (Fn7_d < 1024)
Fn7_2 = (Fn7_d >> 4) * (Fn7_d < 1024)
Fs7_d = (SN_CLOCK_100 + 147998) / 295996 ; 102 F#7/Gb7, 2959.96 Hz
Fs7_1 = (Fs7_d & $0F) * (Fs7_d < 1024)
Fs7_2 = (Fs7_d >> 4) * (Fs7_d < 1024)
Gn7_d = (SN_CLOCK_100 + 156798) / 313596 ; 103 G7, 3135.96 Hz
Gn7_1 = (Gn7_d & $0F) * (Gn7_d < 1024)
Gn7_2 = (Gn7_d >> 4) * (Gn7_d < 1024)
Gs7_d = (SN_CLOCK_100 + 166122) / 332244 ; 104 G#7/Ab7, 3322.44 Hz
Gs7_1 = (Gs7_d & $0F) * (Gs7_d < 1024)
Gs7_2 = (Gs7_d >> 4) * (Gs7_d < 1024)
An7_d = (SN_CLOCK_100 + 176000) / 352000 ; 105 A7, 3520.00 Hz
An7_1 = (An7_d & $0F) * (An7_d < 1024)
An7_2 = (An7_d >> 4) * (An7_d < 1024)
As7_d = (SN_CLOCK_100 + 186465) / 372931 ; 106 A#7/Bb7, 3729.31 Hz
As7_1 = (As7_d & $0F) * (As7_d < 1024)
As7_2 = (As7_d >> 4) * (As7_d < 1024)
Bn7_d = (SN_CLOCK_100 + 197553) / 395107 ; 107 B7, 3951.07 Hz
Bn7_1 = (Bn7_d & $0F) * (Bn7_d < 1024)
Bn7_2 = (Bn7_d >> 4) * (Bn7_d < 1024)
Cn8_d = (SN_CLOCK_100 + 209300) / 418601 ; 108 C8, 4186.01 Hz
Cn8_1 = (Cn8_d & $0F) * (Cn8_d < 1024)
Cn8_2 = (Cn8_d >> 4) * (Cn8_d < 1024)
Cs8_d = (SN_CLOCK_100 + 221746) / 443492 ; 109 C#8/Db8, 4434.92 Hz
Cs8_1 = (Cs8_d & $0F) * (Cs8_d < 1024)
Cs8_2 = (Cs8_d >> 4) * (Cs8_d < 1024)
Dn8_d = (SN_CLOCK_100 + 234932) / 469864 ; 110 D8, 4698.64 Hz
Dn8_1 = (Dn8_d & $0F) * (Dn8_d < 1024)
Dn8_2 = (Dn8_d >> 4) * (Dn8_d < 1024)
Ds8_d = (SN_CLOCK_100 + 248901) / 497803 ; 111 D#8/Eb8, 4978.03 Hz
Ds8_1 = (Ds8_d & $0F) * (Ds8_d < 1024)
Ds8_2 = (Ds8_d >> 4) * (Ds8_d < 1024)
En8_d = (SN_CLOCK_100 + 263702) / 527404 ; 112 E8, 5274.04 Hz
En8_1 = (En8_d & $0F) * (En8_d < 1024)
En8_2 = (En8_d >> 4) * (En8_d < 1024)
Fn8_d = (SN_CLOCK_100 + 279382) / 558765 ; 113 F8, 5587.65 Hz
Fn8_1 = (Fn8_d & $0F) * (Fn8_d < 1024)
Fn8_2 = (Fn8_d >> 4) * (Fn8_d < 1024)
Fs8_d = (SN_CLOCK_100 + 295995) / 591991 ; 114 F#8/Gb8, 5919.91 Hz
Fs8_1 = (Fs8_d & $0F) * (Fs8_d < 1024)
Fs8_2 = (Fs8_d >> 4) * (Fs8_d < 1024)
Gn8_d = (SN_CLOCK_100 + 313596) / 627193 ; 115 G8, 6271.93 Hz
Gn8_1 = (Gn8_d & $0F) * (Gn8_d < 1024)
Gn8_2 = (Gn8_d >> 4) * (Gn8_d < 1024)
Gs8_d = (SN_CLOCK_100 + 332244) / 664488 ; 116 G#8/Ab8, 6644.88 Hz
Gs8_1 = (Gs8_d & $0F) * (Gs8_d < 1024)
Gs8_2 = (Gs8_d >> 4) * (Gs8_d < 1024)
An8_d = (SN_CLOCK_100 + 352000) / 704000 ; 117 A8, 7040.00 Hz
An8_1 = (An8_d & $0F) * (An8_d < 1024)
An8_2 = (An8_d >> 4) * (An8_d < 1024)
As8_d = (SN_CLOCK_100 + 372931) / 745862 ; 118 A#8/Bb8, 7458.62 Hz
As8_1 = (As8_d & $0F) * (As8_d < 1024)
As8_2 = (As8_d >> 4) * (As8_d < 1024)
Bn8_d = (SN_CLOCK_100 + 395106) / 790213 ; 119 B8, 7902.13 Hz
Bn8_1 = (Bn8_d & $0F) * (Bn8_d < 1024)
Bn8_2 = (Bn8_d >> 4) * (Bn8_d < 1024)
