EESchema Schematic File Version 4
EELAYER 30 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 8 10
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
$Comp
L 6502:DS1813 U1
U 1 1 60D28CF0
P 1550 2150
F 0 "U1" H 1322 2196 50  0000 R CNN
F 1 "DS1813" H 1322 2105 50  0000 R CNN
F 2 "Package_TO_SOT_THT:TO-92_Inline" H 1550 1750 50  0001 C CNN
F 3 "" H 1550 2150 50  0001 C CNN
	1    1550 2150
	1    0    0    -1  
$EndComp
Text GLabel 1450 1500 0    50   Input ~ 0
+5V
Text GLabel 1450 2800 0    50   Input ~ 0
GND
Wire Wire Line
	1450 2800 1550 2800
Wire Wire Line
	1550 2800 1550 2700
Wire Wire Line
	1450 1500 1550 1500
Wire Wire Line
	1550 1500 1550 1600
$Comp
L Switch:SW_Push SW1
U 1 1 60D29663
P 2050 2450
F 0 "SW1" V 2004 2598 50  0000 L CNN
F 1 "SW_Push" V 2095 2598 50  0000 L CNN
F 2 "" H 2050 2650 50  0001 C CNN
F 3 "~" H 2050 2650 50  0001 C CNN
	1    2050 2450
	0    1    1    0   
$EndComp
Wire Wire Line
	1550 2800 2050 2800
Wire Wire Line
	2050 2800 2050 2650
Connection ~ 1550 2800
Wire Wire Line
	1950 2150 2050 2150
Wire Wire Line
	2050 2150 2050 2250
$Comp
L Connector:AVR-ISP-6 J1
U 1 1 60D2A55E
P 2800 1450
F 0 "J1" V 2333 1500 50  0000 C CNN
F 1 "AVR-ISP-6" V 2424 1500 50  0000 C CNN
F 2 "" V 2550 1500 50  0001 C CNN
F 3 " ~" H 1525 900 50  0001 C CNN
	1    2800 1450
	0    1    1    0   
$EndComp
Text GLabel 2300 1350 0    50   Input ~ 0
GND
Wire Wire Line
	2300 1350 2400 1350
Wire Wire Line
	2050 2150 2200 2150
Wire Wire Line
	2700 2150 2700 1850
Connection ~ 2050 2150
$Comp
L MCU_Microchip_ATmega:ATmega328P-PU U2
U 1 1 60D376F7
P 4700 2950
F 0 "U2" V 4600 3000 50  0000 C CNN
F 1 "ATmega328P-PU" V 4500 2950 50  0000 C CNN
F 2 "Package_DIP:DIP-28_W7.62mm" H 4700 2950 50  0001 C CIN
F 3 "http://ww1.microchip.com/downloads/en/DeviceDoc/ATmega328_P%20AVR%20MCU%20with%20picoPower%20Technology%20Data%20Sheet%2040001984A.pdf" H 4700 2950 50  0001 C CNN
	1    4700 2950
	0    -1   -1   0   
$EndComp
Wire Wire Line
	2700 2150 5000 2150
Wire Wire Line
	5000 2150 5000 2350
Connection ~ 2700 2150
Text GLabel 2800 2850 0    50   Input ~ 0
+5V
Wire Wire Line
	2800 2850 2900 2850
Wire Wire Line
	3100 2850 3100 2950
Wire Wire Line
	3100 2950 3200 2950
Connection ~ 3100 2850
Wire Wire Line
	3100 2850 3200 2850
Text GLabel 6300 2950 2    50   Input ~ 0
GND
Wire Wire Line
	6300 2950 6200 2950
Wire Wire Line
	2800 1850 2800 2250
Wire Wire Line
	2800 2250 4000 2250
Wire Wire Line
	4000 2250 4000 2350
Wire Wire Line
	3900 2350 3900 1950
Wire Wire Line
	3900 1950 3000 1950
Wire Wire Line
	3000 1950 3000 1850
Wire Wire Line
	2900 1850 2900 2050
Wire Wire Line
	2900 2050 3800 2050
Wire Wire Line
	3800 2050 3800 2350
$Comp
L Device:C_Small C1
U 1 1 60D47311
P 1750 1500
F 0 "C1" V 1979 1500 50  0000 C CNN
F 1 "100nF" V 1888 1500 50  0000 C CNN
F 2 "" H 1750 1500 50  0001 C CNN
F 3 "~" H 1750 1500 50  0001 C CNN
	1    1750 1500
	0    -1   -1   0   
$EndComp
Text GLabel 1950 1500 2    50   Input ~ 0
GND
Wire Wire Line
	1550 1500 1650 1500
Connection ~ 1550 1500
Wire Wire Line
	1850 1500 1950 1500
$Comp
L Device:C_Small C3
U 1 1 60D490AF
P 3150 3650
F 0 "C3" V 2921 3650 50  0000 C CNN
F 1 "100nF" V 3012 3650 50  0000 C CNN
F 2 "" H 3150 3650 50  0001 C CNN
F 3 "~" H 3150 3650 50  0001 C CNN
	1    3150 3650
	0    1    1    0   
$EndComp
Wire Wire Line
	3250 3650 3500 3650
Wire Wire Line
	3500 3650 3500 3550
Text GLabel 2950 3650 0    50   Input ~ 0
GND
Wire Wire Line
	2950 3650 3050 3650
$Comp
L Device:C_Small C2
U 1 1 60D4C44B
P 2900 3050
F 0 "C2" H 2992 3096 50  0000 L CNN
F 1 "100nF" H 2992 3005 50  0000 L CNN
F 2 "" H 2900 3050 50  0001 C CNN
F 3 "~" H 2900 3050 50  0001 C CNN
	1    2900 3050
	1    0    0    -1  
$EndComp
Text GLabel 2800 3250 0    50   Input ~ 0
GND
Wire Wire Line
	2800 3250 2900 3250
Wire Wire Line
	2900 3250 2900 3150
Wire Wire Line
	2900 2950 2900 2850
Connection ~ 2900 2850
Wire Wire Line
	2900 2850 3100 2850
$Comp
L Connector:TestPoint TP1
U 1 1 60D4E0FE
P 2200 2050
F 0 "TP1" H 2258 2168 50  0000 L CNN
F 1 "TestPoint" H 2258 2077 50  0000 L CNN
F 2 "" H 2400 2050 50  0001 C CNN
F 3 "~" H 2400 2050 50  0001 C CNN
	1    2200 2050
	1    0    0    -1  
$EndComp
Wire Wire Line
	2200 2050 2200 2150
Connection ~ 2200 2150
Wire Wire Line
	2200 2150 2700 2150
NoConn ~ 3300 1350
$EndSCHEMATC