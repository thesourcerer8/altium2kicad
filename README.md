altium2kicad
============

Altium to KiCad converter for PCB and schematics

System requirements: Perl, FreeCAD

To convert your Altium project to KiCad:

Go to the directory with your .PcbDoc and .SchDoc files and run:

* unpack.pl (it unpacks the .PcbDoc and .SchDoc files into subdirectores)
* Run FreeCAD, open and execute the macro step2wrl.FCMacro (it converts the step files to wrl)
* convertschema.pl (it converts the schematics from the subdirectories to .sch and -cache.lib files)
* convertpcb.pl (it converts the PCB to .kicad_pcb files)

Due to the huge differences between Altium and KiCad, the weak fileformat documentation and the high complexity of the fileformats, this converter cannot guarantee the quality of the conversion. Please verify the output of the converter
If this converter does not work for your files, feel free to provide your files and screenshots of how they do look like and how they should look like, and I will try to help.

Currently known Limitations of KiCad:
* Bezier curves for component symbols -> WONTFIX -> Workaround with linearization
* Multi-line Text Frames
* A GND symbol with multiple horizontal lines arranged as a triangle
* Individual colors for single objects like lines, ...
* Ellipse
* Round Rectangle
* Elliptical Arc
* Rigid-Flex
* STEP file support  -> Will be fixed in the future, intermediate Workaround: Conversion with FreeCAD
