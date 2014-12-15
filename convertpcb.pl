#!/usr/bin/perl -w
use strict;
use Compress::Zlib;

#use Math::Bezier;

# Things that are missing in KiCad:
# More than 32 layers
# Multi-line Text Frames (Workaround: The text can be rendered by the converter)
# A GND symbol with multiple horizontal lines arranged as a triangle
# Individual colors for single objects like lines, ...
# Ellipse (Workaround: we could approximate them with Polylines)
# Round Rectangle (Workaround: we could approximate them with Polylines + Arcs)
# Elliptical Arc (Workaround: we could approximate them with Polylines)
# Element Classes (All Top Components, All Bottom Components, HDMI, Power, All Resistors...)
# Board regions for Rigid-Flex
# Support for STEP files

# Things that are missing in Altium:
# The Zone-Fill-Polygons are not saved in the file. Workaround: In KiCad, select the zone tool, right-click on an empty area, then "Fill all zones"

my $current_status=<<EOF
Advanced Placer Options6.dat # Not needed
Arcs6.dat # NEEDED
Board6.dat # Here are various global infos about the whole board and about the layers
BoardRegions.dat # Here we likely have only 1 region for Novena. Keepouts are defined here. KiCad does not have a Region concept yet.
Classes6.dat # Interesting, but KiCAD does not have classes
ComponentBodies6.dat # Done.
Components6.dat # NEEDED.
Connections6.dat # Empty
Coordinates6.dat # Empty
Design Rule Checker Options6.dat # Not needed
DifferentialPairs6.dat # To be done later
Dimensions6.dat # Annotations about the dimensions
EmbeddedBoards6.dat # Empty
EmbeddedFonts6.dat # 2 Fonts, we don´t need them
Embeddeds6.dat # Empty
ExtendedPrimitiveInformation.dat # Empty
FileVersionInfo.dat # Messages for when the file is opened in older Altium versions that do not support certain features in this fileformat
Fills6.dat # Needs to be verified, are they really rectangular?
FromTos6.dat # Empty
Models.dat # Done
ModelsNoEmbed.dat # Empty
Nets6.dat # Needed
Pads6.dat # Important
Pin Swap Options6.dat # Only 1 line, likely not needed
Polygons6.dat # Done
Regions6.dat #
Rules6.dat # Not important
ShapeBasedComponentBodies6.dat # HALF-Done, do we need more?
ShapeBasedRegions6.dat # Not needed, I guess
SmartUnions.dat # Empty
Texts.dat # Warnings for older Altium versions, I think we don´t need to support those ;-)
Texts6.dat # Partly done, NEEDED
Textures.dat # Empty
Tracks6.dat # Done
Vias6.dat # Done
WideStrings6.dat # Seems to be a copy of Texts6, just for Unicode?!?
EOF
;

#Reads a file with one function
sub readfile($)
{
  if(open(RFIN,"<$_[0]"))
  {
    my $old=$/;
    undef $/;
	binmode RFIN;
    my $content=<RFIN>;
    $/=$old;
    close RFIN;
    return($content);
  }
  return "";
}

#Writes a complete file
sub writefile($$)
{
  #print "Writing $_[1] in file $_[0]";
  if(open(MYOUT,">$_[0]"))
  {
    print MYOUT $_[1];
    close MYOUT;
  }
  chmod 0666,$_[0];
}


sub bin2hex($)
{
  my $orig=$_[0];
  my $value="";
  foreach(0 .. length($orig)-1)
  {
    $value.=sprintf("%02X",unpack("C",substr($orig,$_,1)));
  }
  return $value;
}

sub near($$)
{
  my $d=0.01;
  return ($_[0]>$_[1]-$d && $_[0]<$_[1]+$d);
}


sub HandleBinFile 
{
  my ($filename,$recordtype,$headerlen,$nskip,$piped)=@_;
  # filename is the filename of the file to load
  # recordtype is a string that is checked at the beginning of every record
  # headerlen is the length of the header to skip once on the beginning of the file
  # nskip
  # piped is a callback function that gets called with the parameters $piped->(\%d,$data,$header,$line);
  my $model=1;
  my $content=readfile($filename);

  return unless defined($content);
  $content=~s/\x0d\x0a/\x0d/gs;
  return unless length($content)>4;
  
  my $text="";
  my @a=();
  my %h=();
  
  print "Writing to $filename.txt\n";
  open HBOUT,">$filename.txt";
  my $line=0;
  my $pos=0;
  
  while($pos<length($content)-4)
  {
    my $header=substr($content,$pos,$headerlen);
    $pos+=$headerlen;
    my $rtyp=substr($content,$pos,length($recordtype));
	last if($rtyp ne $recordtype);
	$pos+=length($recordtype);
	
	#print "Pos: $pos\n";
    my $len=sprintf("%.5f",unpack("l",substr($content,$pos,4))); 
	$pos+=4;
    #print "len: $len\n";
    my $data=substr($content,$pos,$len);  
	$pos+=$len;
	
    if($data=~m/\n/s)
    {
      #print "Warning: $filename contains newline in record $line!\n";
    }
    $data=~s/\x00$//;

	if(defined($piped))
	{
	  my @a=split '\|',$data;
	  my %d=();
	  foreach my $c(@a)
	  {
  	    #print "$c\n";
        if($c=~m/^([^=]*)=(.*)$/)
	    {
  	      my $name=$1;
		  my $value=$2;
		  $d{$name}=$value;
		  $h{"LAYER*".$1}{$value}=1 if($name=~m/^LAYER\d+(\w+)$/);
		  $h{$name}{$value}=1 if($model);
	    }
	  }
	  # CALLING THE CALLBACK FUNCTION TO HANDLE A RECORD:
	  $piped->(\%d,$data,$header,$line);
    }
	
    push @a,"|LINENO=$line|".$data;
    $text.=$data."\n";
    print HBOUT "|LINENO=$line|".($data=~m/\xff/?bin2hex($data):$data)."\n";
	
	if($nskip)
	{
	  my $nskiptimes=unpack("v",substr($content,$pos,4));
	  #print "nskip: $nskip nskiptimes: $nskiptimes\n";
	  $pos+=4+$nskiptimes*$nskip;
	}
 	$line++;
  }
  if($model)
  {
    print HBOUT "\nModel:\n";
    foreach(sort keys %h)
	{
	  if(scalar(keys %{$h{$_}})>0)
	  {
	    print HBOUT "$_={".join(",",sort keys %{$h{$_}})."}\n";
	  }
	}
  }
  close HBOUT;
}


sub MarkPoint($$)
{
  my $x=$_[0];
  my $y=$_[1];
  my $size=10;
  print OUT "(gr_line (start ".($x-$size)." ".($y-$size).") (end ".($x+$size)." ".($y+$size).") (layer F.SilkS) (width 0.2032))\n";
  print OUT "(gr_line (start ".($x+$size)." ".($y-$size).") (end ".($x-$size)." ".($y+$size).") (layer F.SilkS) (width 0.2032))\n";
  print OUT "(gr_line (start ".($x)." ".($y-$size).") (end ".($x)." ".($y+$size).") (layer F.SilkS) (width 0.2032))\n";
  print OUT "(gr_line (start ".($x-$size)." ".($y).") (end ".($x+$size)." ".($y).") (layer F.SilkS) (width 0.2032))\n";
}

my $USELOGGING=0;

foreach my $filename(glob('"*/Root Entry/Board6/Data.dat"'))
{
  print "Handling $filename\n";
  my $short=$filename; $short=~s/\/Root Entry\/Board6\/Data\.dat$//;

  #foreach my $dat(glob("\"$short/Root Entry/Models/*.dat\""))
  #{
  #  next unless($dat=~m/\d+\.dat/);
  #  #print "Uncompressing STEP File $dat\n";
  #  my $f=readfile($dat);
  #	 $f=~s/\r\n/\n/sg;
  #  my $x = inflateInit();
  #  my $dest = $x->inflate($f);
  #  open OUT,">$dat.step";
  #  binmode OUT;
  #  print OUT $dest;
  #  close OUT;
  #}
  
  my %layername=();
  my %dieltype=();
  my %mechenabled=();
  HandleBinFile($filename,"",0,0,sub {
    my %d=%{$_[0]};
	foreach(keys %d)
	{
	  if($_=~m/^LAYER(\d+)NAME$/)
	  {
	    $layername{$1}=$d{$_};
		#print "$1 -> $d{$_}\n";
	  }
	  if($_=~m/^LAYER(\d+)DIELTYPE$/)
	  {
	    $dieltype{$1}=$d{$_};
		#print "$1 -> $d{$_}\n";
	  }
	  if($_=~m/^LAYER(\d+)MECHENABLED$/)
	  {
	    $mechenabled{$1}=$d{$_};
		#print "$1 -> $d{$_}\n";
	  }
	}
  }); # Board

  my $layers="";
  
  foreach(sort {$a <=> $b} keys %layername)
  {
    my $name=$layername{$_}; $name=~s/ /./g;
	my $diel=$dieltype{$_};
	my $mech=$mechenabled{$_};
	#print "name: $_ ".sprintf("%20s",$name)." $diel $mech\n";
	my %dielmap=("1"=>"power","2"=>"power","0"=>"signal");
	my $id=$_+50;
	# KiCad currently only supports up to 32 layers :-(
    #$layers.="    ($id $name ".$dielmap{$diel}.")\n";
  }
  
  my $layerdoku=<<EOF
KiCad Design with 10 layers:
    (layers
    (0 F.Cu signal)
    (1 In1.Cu signal)
    (2 In2.Cu power)
    (3 In3.Cu power)
    (4 In4.Cu signal)
    (5 In5.Cu signal)
    (6 In6.Cu signal)
    (7 In7.Cu signal)
    (8 In8.Cu signal)
    (31 B.Cu signal)
    (32 B.Adhes user)
    (33 F.Adhes user)
    (34 B.Paste user)
    (35 F.Paste user)
    (36 B.SilkS user)
    (37 F.SilkS user)
    (38 B.Mask user)
    (39 F.Mask user)
    (40 Dwgs.User user)
    (41 Cmts.User user)
    (42 Eco1.User user)
    (43 Eco2.User user)
    (44 Edge.Cuts user)
    (45 Margin user)
  )
Novena:
      Layer       Name   Dielectric Mechanic
name:  1                  Top 2 FALSE
name:  2          Mid-Layer.1 0 FALSE
name:  3                   L3 2 FALSE
name:  4                   L4 1 FALSE
name:  5          Mid-Layer.4 0 FALSE
name:  6          Mid-Layer.5 0 FALSE
name:  7          Mid-Layer.6 0 FALSE
name:  8          Mid-Layer.7 0 FALSE
name:  9          Mid-Layer.8 0 FALSE
name: 10          Mid-Layer.9 0 FALSE
name: 11                   L7 2 FALSE
name: 12                   L8 1 FALSE
name: 13         Mid-Layer.12 0 FALSE
name: 14         Mid-Layer.13 0 FALSE
name: 15         Mid-Layer.14 0 FALSE
name: 16         Mid-Layer.15 0 FALSE
name: 17         Mid-Layer.16 0 FALSE
name: 18         Mid-Layer.17 0 FALSE
name: 19         Mid-Layer.18 0 FALSE
name: 20         Mid-Layer.19 0 FALSE
name: 21         Mid-Layer.20 0 FALSE
name: 22         Mid-Layer.21 0 FALSE
name: 23         Mid-Layer.22 0 FALSE
name: 24         Mid-Layer.23 0 FALSE
name: 25         Mid-Layer.24 0 FALSE
name: 26         Mid-Layer.25 0 FALSE
name: 27         Mid-Layer.26 0 FALSE
name: 28         Mid-Layer.27 0 FALSE
name: 29         Mid-Layer.28 0 FALSE
name: 30         Mid-Layer.29 0 FALSE
name: 31         Mid-Layer.30 0 FALSE
name: 32                  Bot 0 FALSE
name: 33          Top.Overlay 0 FALSE
name: 34       Bottom.Overlay 0 FALSE
name: 35            Top.Paste 0 FALSE
name: 36         Bottom.Paste 0 FALSE
name: 37           Top.Solder 0 FALSE
name: 38        Bottom.Solder 0 FALSE
name: 39               L2-GND 1 FALSE
name: 40               L5-PWR 2 FALSE
name: 41               L6-PWR 1 FALSE
name: 42               L9-GND 2 FALSE
name: 43     Internal.Plane.5 0 FALSE
name: 44     Internal.Plane.6 0 FALSE
name: 45     Internal.Plane.7 0 FALSE
name: 46     Internal.Plane.8 0 FALSE
name: 47     Internal.Plane.9 0 FALSE
name: 48    Internal.Plane.10 0 FALSE
name: 49    Internal.Plane.11 0 FALSE
name: 50    Internal.Plane.12 0 FALSE
name: 51    Internal.Plane.13 0 FALSE
name: 52    Internal.Plane.14 0 FALSE
name: 53    Internal.Plane.15 0 FALSE
name: 54    Internal.Plane.16 0 FALSE
name: 55          Drill.Guide 0 FALSE
name: 56       Keep-Out.Layer 0 FALSE
name: 57         Mechanical.1 0 TRUE
name: 58         Mechanical.2 0 TRUE
name: 59         Mechanical.3 0 TRUE
name: 60         Mechanical.4 0 TRUE
name: 61         Mechanical.5 0 FALSE
name: 62         Mechanical.6 0 FALSE
name: 63         Mechanical.7 0 FALSE
name: 64         Mechanical.8 0 FALSE
name: 65         Mechanical.9 0 FALSE
name: 66        Mechanical.10 0 FALSE
name: 67        Mechanical.11 0 FALSE
name: 68        Mechanical.12 0 FALSE
name: 69        Mechanical.13 0 TRUE
name: 70        Mechanical.14 0 FALSE
name: 71        Mechanical.15 0 TRUE
name: 72        Mechanical.16 0 FALSE
name: 73        Drill.Drawing 0 FALSE
name: 74          Multi-Layer 0 FALSE
name: 75          Connections 0 FALSE
name: 76           Background 0 FALSE
name: 77    DRC.Error.Markers 0 FALSE
name: 78           Selections 0 FALSE
name: 79       Visible.Grid.1 0 FALSE
name: 80       Visible.Grid.2 0 FALSE
name: 81            Pad.Holes 0 FALSE
name: 82            Via.Holes 0 FALSE

EOF
;
  
  
  our %modelname=();
  our %modelrotx=();
  our %modelroty=();
  our %modelrotz=();
  our %modeldz=();
  our %modelwrl=();
  
  our $modelid="";
  
  HandleBinFile("$short/Root Entry/Models/Data.dat","",0,0,sub 
  { 
    my $fn=$_[0]{'NAME'};
	#print "".((-f "$short/Root Entry/Models/$fn")?"File exists.\n":"File $fn does NOT EXIST!\n");
	$fn=~s/\.STEP$//i;$fn=~s/\.stp$//i;
	#print "R:".$_[0]{'ID'}."->$fn\n";
    $modelname{$_[0]{'ID'}}=$fn;
	$modelrotx{$_[0]{'ID'}}=360-$_[0]{'ROTX'}; # I think those (ROT*, DZ) are the default values for new placements of the same device, but they can be overridden on specific instances, so we don´t need them
	$modelroty{$_[0]{'ID'}}=360-$_[0]{'ROTY'};
	$modelrotz{$_[0]{'ID'}}=360-$_[0]{'ROTZ'};
	$modeldz{$_[0]{'ID'}}=$_[0]{'DZ'};
	$modelwrl{$_[0]{'ID'}}="$short/Root Entry/Models/$_[3].wrl";
  });
  
  

  print "Writing PCB to $short.kicad_pcb\n";
  open OUT,">$short.kicad_pcb";

  #_800001ff
  
  print OUT <<EOF
(kicad_pcb (version 4) (host pcbnew "(2014-07-21 BZR 5016)-product")

  (general
    (links 0)
    (no_connects 0)
    (area 0 0 0 0)
    (thickness 1.6)
    (drawings 1)
    (tracks 0)
    (zones 0)
    (modules 42)
    (nets 2)
  )

  (page A4)
  (layers
    (0 F.Cu signal)
	(1 In1.Cu signal)
    (2 In2.Cu power)
    (3 In3.Cu power)
    (4 In4.Cu signal)
    (5 In5.Cu signal)
    (6 In6.Cu signal)
    (7 In7.Cu signal)
    (8 In8.Cu signal)
    (31 B.Cu signal)
    (32 B.Adhes user)
    (33 F.Adhes user)
    (34 B.Paste user)
    (35 F.Paste user)
    (36 B.SilkS user)
    (37 F.SilkS user)
    (38 B.Mask user)
    (39 F.Mask user)
    (40 Dwgs.User user)
    (41 Cmts.User user)
    (42 Eco1.User user)
    (43 Eco2.User user)
    (44 Edge.Cuts user)
    (45 Margin user)
    (46 B.CrtYd user)
    (47 F.CrtYd user)
    (48 B.Fab user)
    (49 F.Fab user)
$layers
  )

  (setup
    (last_trace_width 0.254)
    (trace_clearance 0.254)
    (zone_clearance 0.508)
    (zone_45_only no)
    (trace_min 0.254)
    (segment_width 0.2)
    (edge_width 0.1)
    (via_size 0.889)
    (via_drill 0.635)
    (via_min_size 0.889)
    (via_min_drill 0.508)
    (uvia_size 0.508)
    (uvia_drill 0.127)
    (uvias_allowed no)
    (uvia_min_size 0.508)
    (uvia_min_drill 0.127)
    (pcb_text_width 0.3)
    (pcb_text_size 1.5 1.5)
    (mod_edge_width 0.15)
    (mod_text_size 1 1)
    (mod_text_width 0.15)
    (pad_size 1.5 1.5)
    (pad_drill 0.6)
    (pad_to_mask_clearance 0)
    (aux_axis_origin 0 0)
    (visible_elements FFFFFF7F)
    (pcbplotparams
      (layerselection 262143)
      (usegerberextensions false)
      (excludeedgelayer true)
      (linewidth 0.100000)
      (plotframeref false)
      (viasonmask false)
      (mode 1)
      (useauxorigin false)
      (hpglpennumber 1)
      (hpglpenspeed 20)
      (hpglpendiameter 15)
      (hpglpenoverlay 2)
      (psnegative false)
      (psa4output false)
      (plotreference true)
      (plotvalue true)
      (plotinvisibletext false)
      (padsonsilk false)
      (subtractmaskfromsilk false)
      (outputformat 1)
      (mirror false)
      (drillshape 0)
      (scaleselection 1)
      (outputdirectory "GerberOutput/"))
  )

  (net 0 "")
  (net 1 "Net1")

  (net_class Default "This is the default net class."
    (clearance 0.254)
    (trace_width 0.254)
    (via_dia 0.889)
    (via_drill 0.635)
    (uvia_dia 0.508)
    (uvia_drill 0.127)
	(add_net Net1)
  )
  
EOF
;
  
  my $faktor=39.370078740158;
  my $fak="0.39370078740158";
  my $xmove=95.3; 
  my $ymove=79.6; 
  #$xmove=50;$ymove=250; # Enable to move everything into the frame, or disable to move it to align to the Gerber-Imports
  
  my %layermap=("1"=>"F.Cu","3"=>"In2.Cu","4"=>"In3.Cu","11"=>"In6.Cu","12"=>"In7.Cu","32"=>"B.Cu","33"=>"F.SilkS","34"=>"B.SilkS",
  "35"=>"F.Paste","36"=>"B.Paste","37"=>"F.Mask",
  "38"=>"B.Mask","39"=>"In1.Cu","40"=>"In4.Cu","41"=>"In5.Cu","42"=>"In8.Cu","74"=>"Eco1.User",
  
  "44"=>"In6.Cu","73"=>"Eco2.User","60"=>"In4.Cu","56"=>"Edge.Cuts",
  ,"69"=>"Eco1.User","59"=>"Eco1.User","71"=>"Eco1.User",
  "57"=>"Eco1.User","58"=>"Eco1.User");
  
  my @layerkeys=keys %layermap;
  foreach(@layerkeys)
  {
    $layermap{$layername{$_}}=$layermap{$_};
    $layermap{uc $layername{$_}}=$layermap{$_};
	#print "$layername{$_}\n";
	if($layername{$_}=~m/Internal\.Plane\.(\d+)/)
	{
	  print "Found plane $1\n";
	  $layermap{"PLANE$1"}=$layermap{$_};
	}
	if($layername{$_}=~m/Mid-Layer\.(\d+)/)
	{
	  $layermap{"MID$1"}=$layermap{$_};
	}
  }
  foreach(1..30)
  {
    $layermap{"MID$_"}=$layermap{$_+1};
  }
  foreach(1..16)
  {
    $layermap{"PLANE$_"}=$layermap{$_+38};
  }
  $layermap{"TOP"}=$layermap{1};
  $layermap{"BOTTOM"}=$layermap{32};
  $layermap{"TOPOVERLAY"}=$layermap{33};
  foreach(sort keys %layermap)
  {
    #print "SORT: $_ -> $layermap{$_}\n";
  }
 
  my %pads=();
  our %unmappedLayers=();
  our %usedlayers=();
  
  sub mapLayer($)
  {
    my $lay=$_[0];
	$usedlayers{$lay}++;
    if(!defined($layermap{$lay}))
	{
	  my $name="undefined"; $name=$1 if($layerdoku=~m/name: *$lay *([\w.]+)/);
      $unmappedLayers{$_[0]}=$name ;
	}
    print "No mapping for Layer ".$_[0]." defined!\n" if(!defined($layermap{$_[0]}));
	return $layermap{$_[0]}; 
  }

  our %A2Kwrl=(
    "Chip_Capacitor_N.PcbLib/Cap Semi"=>"smd/Capacitors/c_1206.wrl",
	"commonpcb.lib/Cap Semi"=>"smd/Capacitors/c_1206.wrl",
    "Miscellaneous Connectors.IntLib/Header 20X2"=>"Pin_Headers/Pin_Header_Straight_2x20.wrl",
	"SOP_65P_N.PcbLib/ADCxx8Sxx2"=>"smd/smd_dil/ssop-16.wrl",
    "TSOP_65P_N.PcbLib/SN74LVC8T245PWR"=>"smd/smd_dil/tssop-24.wrl",
	"Chip_Resistor_N.PcbLib/Res1"=>"smd/resistors/r_1206.wrl",
    "SOT23_5-6Lead_N.PcbLib/RT9706"=>"smt/SOT223.wrl",
	"SOT23_5-6Lead_N.PcbLib/LP2980M5"=>"smt/SOT223.wrl",
	"Chip Diode - 2 Contacts.PcbLib/LED2"=>"Dioden_SMD_Wings3d_RevA_06Sep2012/Dioden_SMD_RevA_31May2013.wrl");
	
  our %A2Kfak=(
    "Miscellaneous Connectors.IntLib/Header 20X2"=>"0.395"
  );  
	
  our $componentid=0;
  our %componentatx=();
  our %componentaty=();
  our %componentlayer=();
  our %kicadwrl=();
  HandleBinFile("$short/Root Entry/Components6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	my $atx=$d{'X'};$atx=~s/mil$//;$atx/=$faktor;$atx-=$xmove;
	$componentatx{$componentid}=$atx;
	#print "\$componentatx{$componentid}=$atx\n";
	my $aty=$d{'Y'};$aty=~s/mil$//;$aty/=$faktor;$aty=$ymove-$aty;
	$componentaty{$componentid}=$aty;
    $componentlayer{$componentid}=$d{'LAYER'};
	
	$kicadwrl{$componentid}=$A2Kwrl{$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'}};
	if(defined($kicadwrl{$componentid}))
	{
	  #print "A2K: ".$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'}." -> ".$A2Kwrl{$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'}}."\n";
	}
	else
	{
	  print "No Mapping for: ".$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'}."\n";
	}
    $componentid++;
  });

  
  #HandleBinFile("$short/Root Entry/Pads6/Data.dat","\x02",0,0, sub 
  {
    my $value=readfile("$short/Root Entry/Pads6/Data.dat");
	$value=~s/\r\n/\n/gs;
	open AOUT,">$short/Root Entry/Pads6/Data.dat.txt";
	my $pos=0;
	my $counter=0;
	while($pos<length($value))
	{
	  my $len=sprintf("%.5f",unpack("l",substr($value,$pos+1,4)));
	  print AOUT bin2hex(substr($value,$pos,5))." ";
	  print AOUT sprintf("A:%10s",bin2hex(substr($value,$pos+5,$len)))." ";
	  my $name=substr($value,$pos+6,$len-1);
	  $pos+=5+$len;


      my $component=unpack("s",substr($value,$pos+30,2));	

	  #print "component:$component\n";
      my $x1=unpack("l",substr($value,$pos+36,4))/$faktor/10000-$xmove; 
	  my $y1=$ymove-unpack("l",substr($value,$pos+40,4))/$faktor/10000;
  	  #MarkPoint($x1,$y1) if($counter eq 2);
	  $x1-=$componentatx{$component} if($component>=0 && defined($componentatx{$component}));
	  $y1-=$componentaty{$component} if($component>=0 && defined($componentaty{$component}));

      $x1=sprintf("%.5f",$x1);
	  $y1=sprintf("%.5f",$y1);
		  
      my $layer=mapLayer(unpack("C",substr($value,$pos+23,1)));

	  my $sx=sprintf("%.5f",unpack("l",substr($value,$pos+44,4))/$faktor/10000);
	  my $sy=sprintf("%.5f",unpack("l",substr($value,$pos+48,4))/$faktor/10000);
	  my $holesize=sprintf("%.5f",unpack("l",substr($value,$pos+68,4))/$faktor/10000);

	  
	  my $dir=unpack("d",substr($value,$pos+75,8)); 
	  
	  my $mdir=($dir==0)?"":" $dir";
	  
	  my %typemap=("2"=>"rect","1"=>"circle");
      my $type=$typemap{unpack("C",substr($value,$pos+72,1))};	  
	  
	  $type="oval" if($type eq "circle" && $sx != $sy);
	  
      my %platemap=("0"=>"FALSE","1"=>"TRUE");
      my $plated=$platemap{unpack("C",substr($value,$pos+83,1))};	  

	  
      my $net=unpack("s",substr($value,$pos+26,2));	  
	  
	  #print "layer:$layer net:$net component=$component type:$type dir:$dir \n";
	  print AOUT bin2hex(substr($value,$pos,143))." ";
	  my $len2=unpack("l",substr($value,$pos+143,4));
	  $pos+=147;
  	  print AOUT bin2hex(substr($value,$pos,$len2))."\n";
      $pos+=$len2;
	  
	  my $width=0.5;

	  print OUT "  (via (at $x1 $y1) (size $holesize) (layers $layer $layer) (net $net))\n" if($type eq "ROUND");
      if($type eq "RECTANGLE" && 0)
      {
 	    print OUT <<EOF
 (gr_text "PAD" (at $x1 $y1$mdir) (layer $layer)
    (effects (font (size $width $width) (thickness 0.1)))
  )
EOF
;
      }

	  my $tp=($holesize==0)?"smd":$plated eq "TRUE"?"thru_hole":"np_thru_hole";
	  my $drill=($holesize==0)?"":" (drill $holesize) ";
	  
	  $pads{$component}.=<<EOF
    (pad "$name" $tp $type (at $x1 $y1$mdir) (size $sx $sy) $drill
      (layers $layer F.Paste F.Mask)
    )
EOF
;
	  
	  $counter++;
	  
	}
    close AOUT;
  
  }#);


  HandleBinFile("$short/Root Entry/ComponentBodies6/Data.dat","",23,16, sub 
  { 
    my %d=%{$_[0]};
	my $header=$_[2];
	my $component=unpack("s",substr($header,12,2));
	#print "Component:$component\n";
	my $id=$d{'MODELID'};
	my $atx=$d{'MODEL.2D.X'};$atx=~s/mil$//;$atx/=$faktor;$atx-=$xmove;
	my $aty=$d{'MODEL.2D.Y'};$aty=~s/mil$//;$aty/=$faktor;$aty=$ymove-$aty;
	
	my $catx=$componentatx{$component};
	
	
    $atx-=$componentatx{$component} if($component>=0 && defined($componentatx{$component}));
	$aty-=$componentaty{$component} if($component>=0 && defined($componentaty{$component}));
	
	$atx=sprintf("%.5f",$atx);
	$aty=sprintf("%.5f",$aty);
	
	#print $d{'MODELID'}."\n";
	if(!defined($modelname{$d{'MODELID'}}))
	{
	  #print "MODELID: $d{'MODELID'}\n";
	}
	my $stp=defined($modelname{$id})?$modelname{$id}:undef; # $d{'IDENTIFIER'}."_". $stp=~s/\{//; $stp=~s/\}//; $stp=$d{'BODYPROJECTION'}; #substr($text,0,10);
	my $layer=defined($d{'V7_LAYER'})?($d{'V7_LAYER'} eq "MECHANICAL1"?"B.Cu":"F.Cu"):"F.Cu";
	print OUT <<EOF
  (gr_text $stp (at $atx $aty) (layer $layer)
    (effects (font (size 1.0 1.0) (thickness 0.2)) )
  )
EOF
if(defined($stp)); 


	my $ident=""; $ident.=pack("C",$_) foreach(split(",",$d{'IDENTIFIER'}));
	
	#my $rot=(($modelrotx{$id}||0)+$d{'MODEL.3D.ROTX'})." ".(($modelroty{$id}||0)+$d{'MODEL.3D.ROTY'})." ".(($modelrotz{$id}||0)+$d{'MODEL.3D.ROTZ'});
	my $rot=((360-$d{'MODEL.3D.ROTX'})." ".(360-$d{'MODEL.3D.ROTY'})." ".(360-$d{'MODEL.3D.ROTZ'}));
	#my $rot=(($modelrotx{$id}||0))." ".(($modelroty{$id}||0))." ".(($modelrotz{$id}||0));
	my $mdz=$modeldz{$id}||0; $mdz=~s/mil//; $mdz/=10000000; 
	#my $dz=$d{'MODEL.3D.DZ'}; $dz=~s/mil//; $dz=$mdz; #+
	#$dz/=$faktor; $dz/=1000;
	my $dz=$mdz;
	my $wrl=(defined($modelwrl{$id}) && -f $modelwrl{$id}) ? $modelwrl{$id} : undef;
	mkdir "wrl";
	writefile("wrl/$stp.wrl",readfile($wrl)) if(defined($stp)&& defined($wrl));
	$wrl="wrl/$stp.wrl" if(defined($stp));
	
	#print "wrl: $wrl\n" if(defined($modelwrl{$id}));
	
    if((defined($stp) && -r $wrl) || defined($kicadwrl{$component}))
	{
	  if($component>=0)
	  {
	    #print "Component: $component\n";
		#print "MODEL.2D.X:$d{'MODEL.2D.X'} atx: $atx componentatx: $componentatx{$component}\n";
		#print "MODEL.2D.Y:$d{'MODEL.2D.Y'} aty: $aty componentaty: $componentaty{$component}\n";
		#print "V7_LAYER: $d{'V7_LAYER'}\n";
		#print "componentlayer: $componentlayer{$component}\n";
		#print "".(360-$d{'MODEL.3D.ROTX'})." ".(360-$d{'MODEL.3D.ROTY'})." ".(360-$d{'MODEL.3D.ROTZ'})." vs. ".$modelrotx{$id}." ".$modelroty{$id}." ".$modelrotz{$id}."\n";
		
		my $dx=sprintf("%.5f",$atx/25.4);
		my $dy=sprintf("%.5f",-$aty/25.4);
		$dy=-$dy if(defined($componentlayer{$component}) && $componentlayer{$component} eq "BOTTOM"); # The Y axis seems to be mirrored on bottom elements
		my $lfak=$fak;
		if(defined($stp) && -r $wrl)
		{
		  $wrl="./$wrl";
		}
		else
		{
		  $wrl=$kicadwrl{$component};
		  $fak=1;
		}
		
	    $pads{$component}.=<<EOF
	(model "$wrl"
      (at (xyz $dx $dy $dz))
      (scale (xyz $lfak $lfak $lfak))
      (rotate (xyz $rot))
    )
EOF
;
	  }
    }
	else
	{
	  print "NOT FOUND: $stp.wrl\n" if(defined($stp));
	}
  });
  
  $componentid=0;
  HandleBinFile("$short/Root Entry/Components6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	
	my $atx=$d{'X'};$atx=~s/mil$//;$atx/=$faktor;$atx-=$xmove;
	my $aty=$d{'Y'};$aty=~s/mil$//;$aty/=$faktor;$aty=$ymove-$aty;
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
    my $stp=$d{'SOURCEDESIGNATOR'};
    print OUT <<EOF
 (module $stp (layer $layer) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at $atx $aty)
    (path /539EEC0F)
    (attr smd)
	$pads{$componentid}
  )
EOF
;
    $componentid++;
  });


  HandleBinFile("$short/Root Entry/Nets6/Data.dat","",0,0, sub 
  { 
  });


  HandleBinFile("$short/Root Entry/Arcs6/Data.dat","\x01",0,0,sub 
  { 
    my $fn=$_[0]{'NAME'};
    my $value=$_[1];
  	my $x=sprintf("%.5f",unpack("l",substr($value,13,4))/$faktor/10000-$xmove);
	my $y=sprintf("%.5f",$ymove-unpack("l",substr($value,17,4))/$faktor/10000);
	my $width=sprintf("%.5f",unpack("l",substr($value,21,4))/$faktor/10000);
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Undefined";
	#print "layer:$layer x:$x y:$y width:$width\n";
	#my $layer2=mapLayer(unpack("C",substr($value,1,1))) || "B.Cu";
	#print "".((-f "$short/Root Entry/Models/$fn")?"File exists.\n":"File $fn does NOT EXIST!\n");
	#$fn=~s/\.STEP$//i;$fn=~s/\.stp$//i;
	#print "R:".$_[0]{'ID'}."->$fn\n";
    #$modelname{$_[0]{'ID'}}=$fn;
  });

  
  my @gerbers=split"\n",readfile('novena_pvt1_e_gerbers\Gerbers.kicad_pcb');
  my @g=();
  @{$g[0]}=split"\n",readfile('novena_pvt1_e_gerbers\GTL.kicad_pcb');
  @{$g[1]}=split"\n",readfile('novena_pvt1_e_gerbers\GP1.kicad_pcb');
  @{$g[2]}=split"\n",readfile('novena_pvt1_e_gerbers\G1.kicad_pcb');
  @{$g[3]}=split"\n",readfile('novena_pvt1_e_gerbers\G2.kicad_pcb');
  @{$g[4]}=split"\n",readfile('novena_pvt1_e_gerbers\GP2.kicad_pcb');
  @{$g[5]}=split"\n",readfile('novena_pvt1_e_gerbers\GP3.kicad_pcb');
  @{$g[6]}=split"\n",readfile('novena_pvt1_e_gerbers\G3.kicad_pcb');
  @{$g[7]}=split"\n",readfile('novena_pvt1_e_gerbers\G4.kicad_pcb');
  @{$g[8]}=split"\n",readfile('novena_pvt1_e_gerbers\GP4.kicad_pcb');
  @{$g[9]}=split"\n",readfile('novena_pvt1_e_gerbers\GBL.kicad_pcb');
  
  my $count=0;
  HandleBinFile("$short/Root Entry/Vias6/Data.dat","\x03",0,0, sub 
  { 
    my $value=$_[1];
    my $debug=($count<100);
    #print bin2hex($value)."\n"; # if($debug);
  	my $x=sprintf("%.5f",unpack("l",substr($value,13,4))/$faktor/10000-$xmove);
	my $y=sprintf("%.5f",$ymove-unpack("l",substr($value,17,4))/$faktor/10000);
	my $width=sprintf("%.5f",unpack("l",substr($value,21,4))/$faktor/10000);
	my $layer1="F.Cu"; # mapLayer(unpack("C",substr($value,0,1))); # || "F.Cu"; # Since Novena does not have any Blind or Buried Vias
	my $layer2="B.Cu"; # mapLayer(unpack("C",substr($value,1,1))); # || "B.Cu";
	#print "Layer: $layer1 -> $layer2\n";
	#print "Koordinaten:\n" if($debug);
	#print "x:$x y:$y width:$width\n" if($debug);
	print OUT "  (via (at $x $y) (size $width) (layers $layer1 $layer2) (net 1))\n";
	
	if(0) # $count>19000 && !($count%50))
	{
	  #print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 1))\n";	  
	  my @foundlayers=();
	  my $firstlayer="";
	  my $lastlayer="";
	  foreach my $layer(0 .. 9)
	  {
	    my $founds=0;
		my $foundpos="";
	    foreach my $gerber (@{$g[$layer]})
	    {
		 #(via (at 57.09996 -56.09996) (size 0.4572) (layers F.Cu B.Cu))
  	      if($gerber=~m/\(via \(at (-?\d+\.?\d*) (-?\d+\.?\d*)\) \(size (-?\d+\.?\d*)\) \(layers (\w+\.?\w*) (\w+\.?\w*)\)\)/)
		  { 
		    my ($gx,$gy,$size,$glayer1,$glayer2)=($1,$2,$3,$4,$5);
		    if(near($x,$gx) && near($y,$gy))
		    {
		      $foundpos=$gerber;
			  $founds++;
		    }
		  }
		}
		if($founds==1)
		{
		  $foundlayers[$layer]=$foundpos;
		  $firstlayer=$layer if($firstlayer eq "");
		  $lastlayer=$layer;
		}
        print "Layer$layer:$founds\n";
	  }
	  print "count: $count Firstlayer: $firstlayer Lastlayer: $lastlayer ".bin2hex($value)."\n"; # if(!($firstlayer==0 && $lastlayer==9));
	  #print "We found ".scalar(@found)." matches layer:$foundlayer!\n";
	  #if(scalar(@found)==1)
      {
        #print "$count: Exactly 1 match found for layer $foundlayer:\n";
	    #if(!defined($widths{$foundlayer}) || scalar(@{$widths{$foundlayer}})<15)
	    {
  	      #push @{$widths{$foundlayer}},bin2hex($value);
		  #print "Gerber: $found[0]\n";
 	      #print "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer B.Paste) (net 1))\n";
     	  #print OUT "  (segment (start $x1 $y1) (end $x1 2000) (width $width) (layer B.Paste) (net 1))\n";
	      #print OUT "  (segment (start $x2 $y2) (end $x2 2000) (width $width) (layer B.Paste) (net 1))\n";
	      #print "DEBUG: ".bin2hex($value)."\n\n";
		}
	  }
	}
	$count++;
  });
  
  $count=0; 
  my %widths=();
  
  
  HandleBinFile("$short/Root Entry/Polygons6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	
	my $counter=$_[3];
	my $width=$d{'TRACKWIDTH'}||1;$width=~s/mil$//; #/$faktor/10000;
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
	my $maxpoints=0;
	foreach(keys %d)
	{
	  if(m/^SA(\d+)/)
	  {
	    $maxpoints=$1 if($1>$maxpoints);
      }
	}
	
	#print "Polygontype: $d{'POLYGONTYPE'} maxpoints:$maxpoints\n";

	#return if($d{'POLYGONTYPE'} eq "Polygon");

	if($d{'POLYGONTYPE'} eq "Split Plane" || $d{'HATCHSTYLE'} eq "Solid")
	{
	  print OUT <<EOF
(zone (net 1) (net_name "Net1") (layer $layer) (tstamp 547BA6E6) (hatch edge 0.508)
    (connect_pads thru_hole_only (clearance 0.508))
    (min_thickness 0.254)
    (fill (mode segment) (arc_segments 16) (thermal_gap 0.508) (thermal_bridge_width 0.508))
    (polygon
      (pts     
EOF
;
	
	}
	
	foreach(0 .. $maxpoints-(($d{'POLYGONTYPE'} eq "Polygon" && $d{'HATCHSTYLE'} eq "Solid")?1:0))
	{
	  my $sx=$d{'VX'.$_};$sx=~s/mil$//;$sx/=$faktor;$sx-=$xmove;
	  my $sy=$d{'VY'.$_};$sy=~s/mil$//;$sy/=$faktor;$sy=$ymove-$sy;
	  my $ex=$d{'VX'.($_+1)}||0;$ex=~s/mil$//;$ex/=$faktor;$ex-=$xmove;
	  my $ey=$d{'VY'.($_+1)}||0;$ey=~s/mil$//;$ey/=$faktor;$ey=$ymove-$ey;
      #MarkPoint($sx,$sy) if($d{'POLYGONTYPE'} eq "Split Plane" && $counter eq 1);
	  print OUT "(gr_line (start $sx $sy) (end $ex $ey) (angle 90) (layer $layer) (width 0.2))\n" if($d{'POLYGONTYPE'} eq "Polygon" && $d{'POLYGONOUTLINE'} eq "TRUE");
	  print OUT "(xy $sx $sy) " if($d{'POLYGONTYPE'} eq "Split Plane" || $d{'HATCHSTYLE'} eq "Solid");
	}
	
	if($d{'POLYGONTYPE'} eq "Split Plane" || $d{'HATCHSTYLE'} eq "Solid")
	{
	  print OUT <<EOF
      )
    )
  )
EOF
;
    }
   });
  
  our $cutcounter=0;
  HandleBinFile("$short/Root Entry/Tracks6/Data.dat","\x04",0,0, sub 
  { 
    my $value=$_[1];
	my $component=unpack("s",substr($value,7,2));
    my $x1=sprintf("%.5f",unpack("l",substr($value,13,4))/$faktor/10000-$xmove);
	my $y1=sprintf("%.5f",$ymove-unpack("l",substr($value,17,4))/$faktor/10000);
	my $x2=sprintf("%.5f",unpack("l",substr($value,21,4))/$faktor/10000-$xmove);
	my $y2=sprintf("%.5f",$ymove-unpack("l",substr($value,25,4))/$faktor/10000);
	my $width=sprintf("%.5f",unpack("l",substr($value,29,4))/$faktor/10000);
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Cmts.User";
	
	if($layer =~m/Edge.Cuts/i)
	{
	  $cutcounter++;
	  #$width="0.$cutcounter";
	  #print "  (gr_line (start $x1 $y1) (end $x2 $y2) (layer $layer) (width $width))\n";
	  
	  
	  print OUT "  (gr_line (start $x1 $y1) (end $x2 $y2) (layer $layer) (width $width))\n"; #(angle 45) 
	}
	else
	{
	  print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 1))\n";
	}
	if(0) # $count>19000 && !($count%50))
	{
	  #print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 1))\n";
	  my @found=();
	  my $foundlayer="";
	  foreach my $layer(1 .. 8)
	  {
	    foreach my $gerber (@{$g[$layer]})
	    {
  	      if($gerber=~m/\(segment \(start (-?\d+\.?\d*) (-?\d+\.?\d*)\) \(end (-?\d+\.?\d*) (-?\d+\.?\d*)\) \(width (-?\d+\.?\d*)\) \(layer (\w+\.?\w*)\) \(net (\d+)\)\)/)
		  { 
		     my ($gx1,$gy1,$gx2,$gy2,$gwidth,$glayer,$gnet)=($1,$2,$3,$4,$5,$6,$7);
		     if(near($x1,$gx1) && near($y1,$gy1) && near($x2,$gx2) && near($y2,$gy2))
		     {
		        push @found,$gerber;
			    $foundlayer=$layer;
		     }
		  }
		}
	  }
	  #print "We found ".scalar(@found)." matches layer:$foundlayer!\n";
	  if(scalar(@found)==1)
      {
        print "$count: Exactly 1 match found for layer $foundlayer:\n";

	    if(!defined($widths{$foundlayer}) || scalar(@{$widths{$foundlayer}})<15)
	    {
  	      push @{$widths{$foundlayer}},bin2hex($value);
		  print "Gerber: $found[0]\n";
 	      #print "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer B.Paste) (net 1))\n";
     	  #print OUT "  (segment (start $x1 $y1) (end $x1 2000) (width $width) (layer B.Paste) (net 1))\n";
	      #print OUT "  (segment (start $x2 $y2) (end $x2 2000) (width $width) (layer B.Paste) (net 1))\n";
	      print "DEBUG: ".bin2hex($value)."\n\n";
		}
	  }
	}
	$count++;
  });
  
  foreach my $width(sort keys %widths)
  {
    print $width.": ".$_."\n" foreach(@{$widths{$width}}); 
  }
  
  HandleBinFile("$short/Root Entry/Dimensions6/Data.dat","\x01\x00",0,0, sub 
  { 
    # Bemaßung
    #|SELECTION=FALSE|LAYER=MECHANICAL3|LOCKED=FALSE|POLYGONOUTLINE=FALSE|USERROUTED=TRUE|UNIONINDEX=0|PRIMITIVELOCK=TRUE|
	#DIMENSIONLAYER=MECHANICAL3|DIMENSIONLOCKED=FALSE|OBJECTID=13|DIMENSIONKIND=1|DRCERROR=FALSE|VINDEXFORSAVE=0|
	#LX=3746.9685mil|LY=2678.4822mil|HX=8520.7481mil|HY=3111.1418mil|X1=3751.9685mil|Y1=2720.4725mil|X2=4076.3386mil|Y2=1960.5906mil|
	#TEXTX=8405.5118mil|TEXTY=2720.4725mil|HEIGHT=10mil|LINEWIDTH=10mil|TEXTHEIGHT=60mil|TEXTWIDTH=6mil|FONT=DEFAULT|STYLE=None|
	#TEXTLINEWIDTH=6mil|TEXTPOSITION=Auto|TEXTGAP=10mil|TEXTFORMAT=10|TEXTDIMENSIONUNIT=Millimeters|TEXTPRECISION=2|TEXTPREFIX=|TEXTSUFFIX=mm|
	#ARROWSIZE=60mil|ARROWLINEWIDTH=10mil|ARROWLENGTH=100mil|ARROWPOSITION=Inside|EXTENSIONOFFSET=10mil|EXTENSIONLINEWIDTH=10mil|EXTENSIONPICKGAP=10mil|
	#REFERENCES_COUNT=2|REFERENCE0PRIM=9256|REFERENCE0OBJECTID=4|REFERENCE0OBJECTSTRING=Track|REFERENCE0POINTX=3751.9685mil|
	#REFERENCE0POINTY=3133.8583mil|REFERENCE0ANCHOR=1|REFERENCE1PRIM=9258|REFERENCE1OBJECTID=4|REFERENCE1OBJECTSTRING=Track|
	#REFERENCE1POINTX=8515.7481mil|REFERENCE1POINTY=3133.8583mil|REFERENCE1ANCHOR=1|TEXT1X=5902.9278mil|TEXT1Y=2684.4822mil|TEXT1ANGLE= 0.00000000000000E+0000|TEXT1MIRROR=FALSE|USETTFONTS=FALSE|BOLD=FALSE|ITALIC=FALSE|FONTNAME=Arial|ANGLE= 1.80000000000000E+0002
	return;
  print OUT <<EOF
   (dimension 27.692116 (width 0.3) (layer F.SilkS)
    (gr_text "1,0902 in" (at 62.055381 48.705306 339.3209367) (layer F.SilkS)
      (effects (font (size 1.5 1.5) (thickness 0.3)))
    )
    (feature1 (pts (xy 72.517 60.198) (xy 75.486111 52.331783)))
    (feature2 (pts (xy 46.609 50.419) (xy 49.578111 42.552783)))
    (crossbar (pts (xy 48.624652 45.07883) (xy 74.532652 54.85783)))
    (arrow1a (pts (xy 74.532652 54.85783) (xy 73.271641 55.008664)))
    (arrow1b (pts (xy 74.532652 54.85783) (xy 73.68581 53.911385)))
    (arrow2a (pts (xy 48.624652 45.07883) (xy 49.471494 46.025275)))
    (arrow2b (pts (xy 48.624652 45.07883) (xy 49.885663 44.927996)))
  )
EOF
;
  });

  HandleBinFile("$short/Root Entry/FileVersionInfo/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	foreach my $key (sort keys %d)
	{
	  my $v=$d{$key};
	  my @a=split",",$v;
	  my $msg="";
	  $msg.=pack("C",$_) foreach(@a);
	  #print "$key $msg\n";
	}
  });

  HandleBinFile("$short/Root Entry/Fills6/Data.dat","\x06",0,0, sub 
  { 
    my $value=$_[1];
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Cmts.User";
    my $x1=sprintf("%.5f",unpack("l",substr($value,13,4))/$faktor/10000-$xmove);
	my $y1=sprintf("%.5f",$ymove-unpack("l",substr($value,17,4))/$faktor/10000);
	my $x2=sprintf("%.5f",unpack("l",substr($value,21,4))/$faktor/10000-$xmove);
	my $y2=sprintf("%.5f",$ymove-unpack("l",substr($value,25,4))/$faktor/10000);
    my $dir=sprintf("%.5f",unpack("d",substr($value,29,8))); 
    my $dir2=sprintf("%.5f",unpack("d",substr($value,38,8))); 

	#print "Koordinaten:\n";
	#print "x:$x1 y:$y1 dir:$dir dir2:$dir2\n";
	print OUT <<EOF
	  (zone (net 1) (net_name "Net1") (layer $layer) (tstamp 53EB93DD) (hatch edge 0.508)
    (connect_pads (clearance 0.508))
    (min_thickness 0.254)
    (fill (arc_segments 16) (thermal_gap 0.508) (thermal_bridge_width 0.508))
    (polygon
      (pts
        (xy $x1 $y1) (xy $x2 $y1) (xy $x2 $y2) (xy $x1 $y2)
      )
    )
  )
EOF
;
  });

  
  HandleBinFile("$short/Root Entry/Regions6/Data.dat","\x0b",0,0, sub 
  { 
    my $value=$_[1];
    #print bin2hex($value)."\n"; # if($debug);
	my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean
    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
	my @a=split '\|',$text;
	my %d=();
	foreach my $c(@a)
	{
	  #print "*$c*\n";
      if($c=~m/^([^=]*)=(.*)$/)
	  {
	    $d{$1}=$2;
	  }
	}
	my $layer=mapLayer($d{'V7_LAYER'});
	my $datalen=unpack("l",substr($value,22+$textlen,4))*16;
	my $data=substr($value,22+$textlen+4,$datalen);
	#print bin2hex($data)."\n";
	#print "text: $text\n";
  });
  
  HandleBinFile("$short/Root Entry/ShapeBasedComponentBodies6/Data.dat","\x0c",0,0, sub 
  { 
    my $value=$_[1];
    #print bin2hex($value)."\n"; # if($debug);
	my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean
    #print "  ".bin2hex($unknownheader)."\n";
    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
	my @a=split '\|',$text;
	my %d=();
	foreach my $c(@a)
	{
	  #print " * $c\n";
      if($c=~m/^([^=]*)=(.*)$/)
	  {
	    $d{$1}=$2;
	  }
	}
	#my $layer=mapLayer($d{'V7_LAYER'});
	#print "Layer: $layer\n";
	my $datalen=(unpack("l",substr($value,22+$textlen,4))+1)*37;
	my $data=substr($value,22+$textlen+4,$datalen);
	foreach(0 .. unpack("l",substr($value,22+$textlen,4))-1)
	{
      my $x1=sprintf("%.5f",unpack("l",substr($data,$_*37+1,4))/$faktor/10000-$xmove);
	  my $y1=sprintf("%.5f",$ymove-unpack("l",substr($data,$_*37+5,4))/$faktor/10000);
      my $x2=sprintf("%.5f",unpack("l",substr($data,$_*37+37+1,4))/$faktor/10000-$xmove);
	  my $y2=sprintf("%.5f",$ymove-unpack("l",substr($data,$_*37+37+5,4))/$faktor/10000);
	  print OUT "(gr_line (start $x1 $y1) (end $x2 $y2) (angle 90) (layer F.Adhes) (width 0.2))\n";
	  #print "(gr_line (start $x1 $y1) (end $x2 $y2) (angle 90) (layer F.Adhes) (width 0.2))\n";
	}
	#print "  ".bin2hex($data)."\n";
	#print "text: $text\n";
	#print "\n";
  });
  
  sub ucs2utf($)
  {
    my $r=$_[0]; $r=~s/\x00//gs;
	return $r;
  }
  
  if(1)
  {
    print "Texts6...\n";
    my $content=readfile("$short/Root Entry/Texts6/Data.dat"); $content=~s/\r\n/\n/sg;
	my $pos=0;
	my %seen=();
	while($pos<length($content))
	{
	  last if(substr($content,$pos,1) ne "\x05"); $pos++;
      my $fontlen=unpack("l",substr($content,$pos,4)); $pos+=4;
      my $layer=mapLayer(unpack("C",substr($content,$pos,1))) || "Cmts.User";
	  my $x1=sprintf("%.5f",unpack("l",substr($content,$pos+13,4))/$faktor/10000-$xmove);
	  my $y1=sprintf("%.5f",$ymove-unpack("l",substr($content,$pos+17,4))/$faktor/10000);
      my $width=sprintf("%.5f",unpack("l",substr($content,$pos+21,4))/$faktor/10000);
	  my $dir=unpack("d",substr($content,$pos+27,8)); 
	  my $font=substr($content,$pos,$fontlen); $pos+=$fontlen;
	  my $fontname=ucs2utf(substr($font,46,64));
      my $textlen=unpack("l",substr($content,$pos,4)); $pos+=4;
	  my $text=substr($content,$pos+1,$textlen-1); $pos+=$textlen;
	  #print  bin2hex($font)." $fontname"."   $text $dir\n";
	  $text=~s/"/''/g;
	  print OUT <<EOF
 (gr_text "$text" (at $x1 $y1 $dir) (layer $layer)
    (effects (font (size $width $width) (thickness 0.1)) (justify left))
  )
EOF
;
	}
  } 
  
  if(keys %unmappedLayers)
  {
    print "Unmapped Layers:\n";
    print join ",",map { "\"$_\"=>\"$unmappedLayers{$_}\""} keys %unmappedLayers;
    print "\n";
  }
  
  foreach(sort keys %usedlayers)
  {
    my $name="undefined"; $name=$1 if($layerdoku=~m/name: *$_ *([\w.]+)/);
	my $kic=$layermap{$_};
    print "Used layer: $_ $layername{$_}/$name -> $kic\n";
  }
  
  print OUT ")\n";
}

sub rem0($)
{
  my $d=$_[0]; $d=~s/\x00//g;
  return $d;
}

sub decodeLib($)
{
  my $content=readfile($_[0]);
  print "Decoding $_[0] (".length($content)."Bytes)...\n";
  my $typelen=unpack("C",substr($content,0,1));
  my $type=substr($content,1,$typelen);
  print "typelen: $typelen\n";
  print "type: *$type*\n";
  my $pos=1+$typelen;
  # The rest of the first block looks like garbage
  $pos=256;
  while($pos<length($content))
  {
    print "pos: ".sprintf("%02X",$pos)." ";
    my $recordtype=unpack("C",substr($content,$pos,1));
    if($recordtype==4)
	{
	  if(substr($content,$pos+4,1)ne"\x7C")
	  {
	    my $len=unpack("S",substr($content,$pos+12,2));
	    print "Record 4a with len $len found: ".bin2hex(substr($content,$pos+1,11))."   ".rem0(substr($content,$pos+14,$len))."\n";
	    $pos+=12+2+$len;
      }
	  else
	  {
        my $len=unpack("S",substr($content,$pos+2,2));
        print "Record 4b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	}
    elsif($recordtype==5)
	{
	  if(unpack("C",substr($content,$pos+1,1))==0)
	  {
  	    my $len=unpack("S",substr($content,$pos+2,2));
	    print "Record 5b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	  else
	  {
	    my $len=2*unpack("S",substr($content,$pos+8,2));
	    print "Record 5a with len $len found ".bin2hex(substr($content,$pos+1,7))." ".bin2hex(substr($content,$pos+8,2))." ".rem0(substr($content,$pos+10,$len))."\n";
	    $pos+=8+2+$len;
      }
	}
    elsif($recordtype==2)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  print "Record $recordtype with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
    elsif($recordtype==3)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  print "Record $recordtype with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
    elsif($recordtype==1)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  print "Record 1 with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
	elsif($recordtype==6)
	{
      if(unpack("C",substr($content,$pos+1,1))==0)
	  {
  	    my $len=unpack("S",substr($content,$pos+2,2));
	    print "Record 6b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	  else
	  {
        print "Record 6a with len 266 found ".(substr($content,$pos+1,$recordtype))."\n";
	    $pos+=266;
	  }	
	}
	elsif($recordtype>=7 && $recordtype<=40)
	{
	  print "Record $recordtype with len 256 found: ".substr($content,$pos+1,$recordtype)."\n";
	  $pos+=256;
	  # Rest is garbage, but often just zeroed
	}
	else
	{
	  print "Unknown recordtype $recordtype\n";
	  last;
	}
  }  
}
#decodeLib("commonpcb.lib");

sub decodeSchLib($)
{
  my $content=readfile($_[0]);
  print "Decoding $_[0] (".length($content)." Bytes)...\n";
  my $pos=0;
  while($pos<length($content))
  {
    my $typelen=unpack("S",substr($content,$pos,2));
    my $type=substr($content,$pos+4,$typelen);
	if(substr($type,0,1)eq "|")
	{
      print "pos: $pos typelen: $typelen type: $type\n";
	}
	else
	{
      print "pos: $pos typelen: $typelen type: ".bin2hex(substr($content,$pos+2,$typelen+2))."\n";	
	}
    $pos+=$typelen+4;
  }
}

foreach(glob("'library/Miscellaneous Devices/Root Entry/SchLib/0/Root Entry/*/Data.dat'"))
{
  decodeSchLib($_);
}

sub decodePcbLib($)
{
  my $content=readfile($_[0]);
  print "Decoding $_[0] (".length($content)." Bytes)...\n";
  my $namelen=unpack("S",substr($content,0,2));
  print "Name: ".substr($content,5,$namelen-1)."\n";
  
  my $pos=4+$namelen;
  my $prevtype=-1;
  while($pos<length($content))
  {
    my $type=unpack("C",substr($content,$pos,1));
    my $typelen=unpack("S",substr($content,$pos+1,2));
	$typelen=147+unpack("C",substr($content,$pos+1,1)) if($type==2);
	#print "Searching on pos ".sprintf("%X",$pos+$typelen+5)."\n" if($type==5);
	$typelen+=4+unpack("C",substr($content,$pos+$typelen+5,1)) if($type==5);
	#$typelen=138 if($type==5);
	$typelen=17 if($type==12);
	if($prevtype==0)
	{
	  $pos+=4;
	  print "Pos: ".sprintf("%5d",$pos)." Number: $type\n";
	  foreach(0 .. $type-1)
	  {
	    if($pos>length($content))
		{
		  print "Error in file!\n";
		  last;
		}
	    print "* ".bin2hex(substr($content,$pos,16))."\n";
		$pos+=16;
	  }
	  $prevtype=-1;
	}
	else
	{
	  print "type: $type ";
      my $value=substr($content,$pos+5,$typelen);
	  if(substr($value,0,2)eq "V7")
	  {
        print "pos: ".sprintf("%5d",$pos)." typelen: ".sprintf("%5d",$typelen)." value: $value\n";
  	  }
 	  else
	  {
        print "pos: ".sprintf("%5d",$pos)." typelen: ".sprintf("%5d",$typelen)." value: ".bin2hex(substr($content,$pos,5))." ".bin2hex(substr($content,$pos+5,$typelen))."\n";	
  	  }
      $pos+=$typelen+5;
	  print "Error in decoding!\n" if($pos>length($content));
	  $prevtype=$type;
	}
  }
}

foreach(glob("'library/Miscellaneous Devices/Root Entry/PcbLib/0/Root Entry/*/Data.dat.bin'"))
{
  decodePcbLib($_);
}
