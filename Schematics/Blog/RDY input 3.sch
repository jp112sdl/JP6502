EESchema Schematic File Version 4
EELAYER 30 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 4 10
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
L Oscillator:TCXO-14 X?
U 1 1 6043089A
P 1700 1700
AR Path="/60398E8A/6043089A" Ref="X?"  Part="1" 
AR Path="/604066AD/6043089A" Ref="X1"  Part="1" 
F 0 "X1" H 1356 1746 50  0000 R CNN
F 1 "4MHz" H 1356 1655 50  0000 R CNN
F 2 "Oscillator:Oscillator_DIP-14" H 2150 1350 50  0001 C CNN
F 3 "http://www.golledge.com/pdf/products/tcxos/gtxos14.pdf" H 1600 1700 50  0001 C CNN
	1    1700 1700
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR?
U 1 1 604308A0
P 1700 2100
AR Path="/60398E8A/604308A0" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/604308A0" Ref="#PWR02"  Part="1" 
F 0 "#PWR02" H 1700 1850 50  0001 C CNN
F 1 "GND" H 1705 1927 50  0000 C CNN
F 2 "" H 1700 2100 50  0001 C CNN
F 3 "" H 1700 2100 50  0001 C CNN
	1    1700 2100
	1    0    0    -1  
$EndComp
Wire Wire Line
	1700 2100 1700 2000
$Comp
L power:+5V #PWR?
U 1 1 604308A7
P 1700 1300
AR Path="/60398E8A/604308A7" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/604308A7" Ref="#PWR01"  Part="1" 
F 0 "#PWR01" H 1700 1150 50  0001 C CNN
F 1 "+5V" H 1715 1473 50  0000 C CNN
F 2 "" H 1700 1300 50  0001 C CNN
F 3 "" H 1700 1300 50  0001 C CNN
	1    1700 1300
	1    0    0    -1  
$EndComp
Wire Wire Line
	1700 1300 1700 1400
$Comp
L 74xx:74HC04 U?
U 7 1 604308AE
P 1700 3250
AR Path="/60398E8A/604308AE" Ref="U?"  Part="7" 
AR Path="/604066AD/604308AE" Ref="U1"  Part="7" 
F 0 "U1" H 1930 3296 50  0000 L CNN
F 1 "74HC04" H 1930 3205 50  0000 L CNN
F 2 "" H 1700 3250 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 1700 3250 50  0001 C CNN
	7    1700 3250
	1    0    0    -1  
$EndComp
$Comp
L power:+5V #PWR?
U 1 1 604308B4
P 1700 2650
AR Path="/60398E8A/604308B4" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/604308B4" Ref="#PWR03"  Part="1" 
F 0 "#PWR03" H 1700 2500 50  0001 C CNN
F 1 "+5V" H 1715 2823 50  0000 C CNN
F 2 "" H 1700 2650 50  0001 C CNN
F 3 "" H 1700 2650 50  0001 C CNN
	1    1700 2650
	1    0    0    -1  
$EndComp
Wire Wire Line
	1700 2650 1700 2750
$Comp
L power:GND #PWR?
U 1 1 604308BB
P 1700 3850
AR Path="/60398E8A/604308BB" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/604308BB" Ref="#PWR06"  Part="1" 
F 0 "#PWR06" H 1700 3600 50  0001 C CNN
F 1 "GND" H 1705 3677 50  0000 C CNN
F 2 "" H 1700 3850 50  0001 C CNN
F 3 "" H 1700 3850 50  0001 C CNN
	1    1700 3850
	1    0    0    -1  
$EndComp
Wire Wire Line
	1700 3850 1700 3750
$Comp
L 74xx:74HC04 U?
U 1 1 604308C2
P 2400 1700
AR Path="/60398E8A/604308C2" Ref="U?"  Part="1" 
AR Path="/604066AD/604308C2" Ref="U1"  Part="1" 
F 0 "U1" H 2400 2017 50  0000 C CNN
F 1 "74HC04" H 2400 1926 50  0000 C CNN
F 2 "" H 2400 1700 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 2400 1700 50  0001 C CNN
	1    2400 1700
	1    0    0    -1  
$EndComp
Wire Wire Line
	2000 1700 2100 1700
$Comp
L 74xx:74HC04 U?
U 6 1 604308C9
P 4250 1700
AR Path="/60398E8A/604308C9" Ref="U?"  Part="6" 
AR Path="/604066AD/604308C9" Ref="U1"  Part="6" 
F 0 "U1" H 4250 2017 50  0000 C CNN
F 1 "74HC04" H 4250 1926 50  0000 C CNN
F 2 "" H 4250 1700 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 4250 1700 50  0001 C CNN
	6    4250 1700
	1    0    0    -1  
$EndComp
$Comp
L Connector:TestPoint TP?
U 1 1 604308CF
P 2800 1600
AR Path="/60398E8A/604308CF" Ref="TP?"  Part="1" 
AR Path="/604066AD/604308CF" Ref="TP1"  Part="1" 
F 0 "TP1" H 2858 1718 50  0000 L CNN
F 1 "RDY out" H 2858 1627 50  0000 L CNN
F 2 "" H 3000 1600 50  0001 C CNN
F 3 "~" H 3000 1600 50  0001 C CNN
	1    2800 1600
	1    0    0    -1  
$EndComp
$Comp
L Connector:TestPoint TP?
U 1 1 604308D5
P 3700 1600
AR Path="/60398E8A/604308D5" Ref="TP?"  Part="1" 
AR Path="/604066AD/604308D5" Ref="TP2"  Part="1" 
F 0 "TP2" H 3758 1718 50  0000 L CNN
F 1 "RDY in" H 3758 1627 50  0000 L CNN
F 2 "" H 3900 1600 50  0001 C CNN
F 3 "~" H 3900 1600 50  0001 C CNN
	1    3700 1600
	1    0    0    -1  
$EndComp
NoConn ~ 4550 1700
Wire Wire Line
	2700 1700 2800 1700
Wire Wire Line
	2800 1600 2800 1700
Wire Wire Line
	3700 1600 3700 1700
Wire Wire Line
	3700 1700 3950 1700
$Comp
L 74xx:74HC04 U?
U 2 1 604308E3
P 2900 2850
AR Path="/60398E8A/604308E3" Ref="U?"  Part="2" 
AR Path="/604066AD/604308E3" Ref="U1"  Part="2" 
F 0 "U1" H 2900 3167 50  0000 C CNN
F 1 "74HC04" H 2900 3076 50  0000 C CNN
F 2 "" H 2900 2850 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 2900 2850 50  0001 C CNN
	2    2900 2850
	1    0    0    -1  
$EndComp
$Comp
L 74xx:74HC04 U?
U 3 1 604308E9
P 2900 3400
AR Path="/60398E8A/604308E9" Ref="U?"  Part="3" 
AR Path="/604066AD/604308E9" Ref="U1"  Part="3" 
F 0 "U1" H 2900 3717 50  0000 C CNN
F 1 "74HC04" H 2900 3626 50  0000 C CNN
F 2 "" H 2900 3400 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 2900 3400 50  0001 C CNN
	3    2900 3400
	1    0    0    -1  
$EndComp
$Comp
L 74xx:74HC04 U?
U 4 1 604308EF
P 3900 2850
AR Path="/60398E8A/604308EF" Ref="U?"  Part="4" 
AR Path="/604066AD/604308EF" Ref="U1"  Part="4" 
F 0 "U1" H 3900 3167 50  0000 C CNN
F 1 "74HC04" H 3900 3076 50  0000 C CNN
F 2 "" H 3900 2850 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 3900 2850 50  0001 C CNN
	4    3900 2850
	1    0    0    -1  
$EndComp
$Comp
L 74xx:74HC04 U?
U 5 1 604308F5
P 3900 3400
AR Path="/60398E8A/604308F5" Ref="U?"  Part="5" 
AR Path="/604066AD/604308F5" Ref="U1"  Part="5" 
F 0 "U1" H 3900 3717 50  0000 C CNN
F 1 "74HC04" H 3900 3626 50  0000 C CNN
F 2 "" H 3900 3400 50  0001 C CNN
F 3 "https://assets.nexperia.com/documents/data-sheet/74HC_HCT04.pdf" H 3900 3400 50  0001 C CNN
	5    3900 3400
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR?
U 1 1 604308FB
P 2500 3500
AR Path="/60398E8A/604308FB" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/604308FB" Ref="#PWR04"  Part="1" 
F 0 "#PWR04" H 2500 3250 50  0001 C CNN
F 1 "GND" H 2505 3327 50  0000 C CNN
F 2 "" H 2500 3500 50  0001 C CNN
F 3 "" H 2500 3500 50  0001 C CNN
	1    2500 3500
	1    0    0    -1  
$EndComp
$Comp
L power:GND #PWR?
U 1 1 60430901
P 3500 3500
AR Path="/60398E8A/60430901" Ref="#PWR?"  Part="1" 
AR Path="/604066AD/60430901" Ref="#PWR05"  Part="1" 
F 0 "#PWR05" H 3500 3250 50  0001 C CNN
F 1 "GND" H 3505 3327 50  0000 C CNN
F 2 "" H 3500 3500 50  0001 C CNN
F 3 "" H 3500 3500 50  0001 C CNN
	1    3500 3500
	1    0    0    -1  
$EndComp
Wire Wire Line
	2500 2850 2600 2850
Wire Wire Line
	2500 3400 2600 3400
Connection ~ 2500 3400
Wire Wire Line
	2500 3400 2500 2850
NoConn ~ 3200 3400
NoConn ~ 3200 2850
Wire Wire Line
	3500 3500 3500 3400
Wire Wire Line
	3500 2850 3600 2850
Wire Wire Line
	3500 3400 3600 3400
Connection ~ 3500 3400
Wire Wire Line
	3500 3400 3500 2850
NoConn ~ 4200 3400
NoConn ~ 4200 2850
Wire Wire Line
	2500 3400 2500 3500
$Comp
L Device:R R1
U 1 1 604310DA
P 3350 1700
F 0 "R1" V 3143 1700 50  0000 C CNN
F 1 "470" V 3234 1700 50  0000 C CNN
F 2 "" V 3280 1700 50  0001 C CNN
F 3 "~" H 3350 1700 50  0001 C CNN
	1    3350 1700
	0    1    1    0   
$EndComp
Wire Wire Line
	2800 1700 3200 1700
Connection ~ 2800 1700
Wire Wire Line
	3500 1700 3700 1700
Connection ~ 3700 1700
$EndSCHEMATC