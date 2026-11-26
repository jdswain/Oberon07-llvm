WD1793 disk interface.
The current hardware uses a 720k 3.5 inch disk. This will be emulated.
Allow for two drives.
Command line options to mount disk image. Longer term we could mount actual disk.

Register Map

E000 1793 Status/Cmd
E001 1793 Track
E002 1793 Sector
E003 1793 Data
E004 Not Used
E005 Not Used
E006 Drive Status/Control

Bit Drive Status (Read)
7   /INTRQ from 1793
6   /(INTRQ+DRQ) from 1793
5   Motor on status 0 = On, 1 = Off
4   Not Used
3   Not Used
2   Not Used
1   Not Used
0   Not Used

Bit Drive Control (Write)
7   Density 0 = Double, 1 = Single (Set to 1)
6   Not Used
5   Motor On Control 0 = Off, 1 = On
4   Drive Select 3 (Not Used)
3   Drive Select 2 (Not Used)
2   Drive Select 1
1   Drive Select 0
0   Side Select 0 = Side 0, 1 = Side 1

