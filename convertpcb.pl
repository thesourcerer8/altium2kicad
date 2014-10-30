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
  # piped is whether there are pipe symbols to be split up
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
  my $pos=$headerlen;
  
  while($pos<length($content)-4)
  {
    my $rtyp=substr($content,$pos,length($recordtype));
	last if($rtyp ne $recordtype);
	$pos+=length($recordtype);
	
	#print "Pos: $pos\n";
    my $len=unpack("l",substr($content,$pos,4)); 
	$pos+=4;
    #print "len: $len\n";
    my $data=substr($content,$pos,$len);  
	$pos+=$len;
	
    if($data=~m/\n/s)
    {
      print "Warning: data contains newline!\n";
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
	  $piped->(\%d,$data);
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
	
	
	
    $pos+=$headerlen;
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







my $USELOGGING=0;

foreach my $filename(glob('"*/Root Entry/Board6/Data.dat"'))
{
  print "Handling $filename\n";
  
  my $short=$filename; $short=~s/\/Root Entry\/Board6\/Data\.dat$//;

  foreach my $dat(glob("\"$short/Root Entry/Models/*.dat\""))
  {
    next unless($dat=~m/\d+\.dat/);
    #print "Uncompressing STEP File $dat\n";
    my $f=readfile($dat);
	$f=~s/\r\n/\n/sg;
    my $x = inflateInit();
    my $dest = $x->inflate($f);
    open OUT,">$dat.step";
	binmode OUT;
    print OUT $dest;
    close OUT;
  }
  
  
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

  
  HandleBinFile("$short/Root Entry/Models/Data.dat","",0,0,sub 
  { 
    my $fn=$_[0]{'NAME'};
	#print "".((-f "$short/Root Entry/Models/$fn")?"File exists.\n":"File $fn does NOT EXIST!\n");
	$fn=~s/\.STEP$//i;$fn=~s/\.stp$//i;
	#print "R:".$_[0]{'ID'}."->$fn\n";
    $modelname{$_[0]{'ID'}}=$fn;
	$modelrotx{$_[0]{'ID'}}=$_[0]{'ROTX'};
	$modelroty{$_[0]{'ID'}}=$_[0]{'ROTY'};
	$modelrotz{$_[0]{'ID'}}=$_[0]{'ROTZ'};
	$modeldz{$_[0]{'ID'}}=$_[0]{'DZ'};
	
  });
  
  

  print "Writing PCB to $short.kicad_pcb\n";
  open OUT,">$short.kicad_pcb";

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
    (nets 43)
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
      (layerselection 30001)
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
      (drillshape 1)
      (scaleselection 1)
      (outputdirectory ""))
  )

  (net 0 "")

  (net_class Default "Dies ist die voreingestellte Netzklasse."
    (clearance 0.254)
    (trace_width 0.254)
    (via_dia 0.889)
    (via_drill 0.635)
    (uvia_dia 0.508)
    (uvia_drill 0.127)
  )
  
EOF
;

if(0) {
print OUT <<EOF
 (module SOIC24 (layer F.Cu) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at 84.328 56.769)
    (path /539EEC0F)
    (attr smd)
    (fp_text reference U3 (at 0 -1.524) (layer F.SilkS)
      (effects (font (size 1.016 1.016) (thickness 0.2032)))
    )
    (fp_text value PGA4311 (at 0 1.143) (layer F.SilkS)
      (effects (font (size 1.016 1.016) (thickness 0.2032)))
    )
    (fp_line (start 7.62 -2.794) (end 7.62 2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 -2.794) (end -7.62 2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start 7.62 -2.794) (end -7.62 -2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 -0.635) (end -6.35 -0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -6.35 -0.635) (end -6.35 0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -6.35 0.635) (end -7.62 0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 2.794) (end 7.62 2.794) (layer F.SilkS) (width 0.2032))
    (pad 1 smd rect (at -6.985 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 2 smd rect (at -5.715 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 3 smd rect (at -4.445 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 4 smd rect (at -3.175 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 5 smd rect (at -1.905 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 6 smd rect (at -0.635 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 7 smd rect (at 0.635 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 8 smd rect (at 1.905 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 9 smd rect (at 3.175 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 10 smd rect (at 4.445 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 11 smd rect (at 5.715 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 12 smd rect (at 7.112 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 24 smd rect (at -6.985 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 23 smd rect (at -5.715 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 22 smd rect (at -4.445 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 21 smd rect (at -3.175 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 20 smd rect (at -1.905 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 19 smd rect (at -0.635 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 18 smd rect (at 0.635 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 17 smd rect (at 1.905 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 16 smd rect (at 3.175 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 15 smd rect (at 4.445 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 14 smd rect (at 5.715 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 13 smd rect (at 6.985 -3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (model smd/cms_soj24.wrl
      (at (xyz 0 0 0))
      (scale (xyz 0.5 0.6 0.5))
      (rotate (xyz 0 0 0))
    )
  )
EOF
;
}
  
  my $faktor=39.3700787402;
  my $fak="0.3937007";
  my $xmove=95.3; 
  my $ymove=79.6; 
  $xmove=50;$ymove=250; # Enable to move everything into the frame, or disable to move it to align to the Gerber-Imports
  
  my %layermap=("1"=>"F.Cu","3"=>"In2.Cu","4"=>"In3.Cu","11"=>"In6.Cu","12"=>"In7.Cu","32"=>"B.Cu","33"=>"F.SilkS","34"=>"B.SilkS","35"=>"F.Paste","36"=>"B.Paste","37"=>"F.Mask","38"=>"B.Mask","39"=>"In1.Cu","40"=>"In4.Cu","41"=>"In5.Cu","42"=>"In8.Cu","74"=>"Eco1.User");
  
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
  
  HandleBinFile("$short/Root Entry/ComponentBodies6/Data.dat","",23,16, sub 
  { 
    my %d=%{$_[0]};
	my $id=$d{'MODELID'};
	my $atx=$d{'MODEL.2D.X'};$atx=~s/mil$//;$atx/=$faktor;$atx-=$xmove;
	my $aty=$d{'MODEL.2D.Y'};$aty=~s/mil$//;$aty/=$faktor;$aty=$ymove-$aty;
	#print $d{'MODELID'}."\n";
	if(!defined($modelname{$d{'MODELID'}}))
	{
	  #print "MODELID: $d{'MODELID'}\n";
	}
	my $stp=defined($modelname{$id})?$modelname{$id}:"X"; # $d{'IDENTIFIER'}."_". $stp=~s/\{//; $stp=~s/\}//; $stp=$d{'BODYPROJECTION'}; #substr($text,0,10);
	my $layer=defined($d{'V7_LAYER'})?($d{'V7_LAYER'} eq "MECHANICAL1"?"B.Cu":"F.Cu"):"F.Cu";
	print OUT <<EOF
  (gr_text $stp (at $atx $aty) (layer $layer)
    (effects (font (size 1.0 1.0) (thickness 0.2)) )
  )
EOF
;
	my $ident=""; $ident.=pack("C",$_) foreach(split(",",$d{'IDENTIFIER'}));
	
	#my $rot=(($modelrotx{$id}||0)+$d{'MODEL.3D.ROTX'})." ".(($modelroty{$id}||0)+$d{'MODEL.3D.ROTY'})." ".(($modelrotz{$id}||0)+$d{'MODEL.3D.ROTZ'});
	#my $rot=(($modelrotx{$id}||0)+$d{'MODEL.3D.ROTX'})." ".(($modelroty{$id}||0)+$d{'MODEL.3D.ROTY'})." ".(($modelrotz{$id}||0)+$d{'MODEL.3D.ROTZ'});
	my $rot=(($modelrotx{$id}||0))." ".(($modelroty{$id}||0))." ".(($modelrotz{$id}||0));
	my $mdz=$modeldz{$id}||0; $mdz=~s/mil//; 
	my $dz=$d{'MODEL.3D.DZ'}; $dz=~s/mil//; $dz+=$mdz; $dz/=$faktor; $dz/=1000;
    if(-r "wrl/$stp.wrl")
	{
	  #print "Found $stp.wrl\n";
print OUT <<EOF
 (module $stp (layer $layer) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at $atx $aty)
    (path /539EEC0F)
    (attr smd)
    (fp_text reference U$ident (at 0 -1.524) (layer F.SilkS)
      (effects (font (size 1.016 1.016) (thickness 0.2032)))
    )
    (fp_text value $stp	(at 0 1.143) (layer F.SilkS)
      (effects (font (size 1.016 1.016) (thickness 0.2032)))
    )
    (fp_line (start 7.62 -2.794) (end 7.62 2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 -2.794) (end -7.62 2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start 7.62 -2.794) (end -7.62 -2.794) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 -0.635) (end -6.35 -0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -6.35 -0.635) (end -6.35 0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -6.35 0.635) (end -7.62 0.635) (layer F.SilkS) (width 0.2032))
    (fp_line (start -7.62 2.794) (end 7.62 2.794) (layer F.SilkS) (width 0.2032))
    (pad 1 smd rect (at -6.985 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (pad 2 smd rect (at -5.715 3.81) (size 0.762 1.524)
      (layers F.Cu F.Paste F.Mask)
    )
    (model ./wrl/$stp.wrl
      (at (xyz 0 0 0))
      (scale (xyz $fak $fak $fak))
      (rotate (xyz $rot))
    )
  )
EOF
;
    }
	else
	{
	  #print "NOT FOUND: $stp.wrl\n" if($stp ne "X");
	}


  });

  HandleBinFile("$short/Root Entry/Components6/Data.dat","",0,0, sub 
  { 
  });



  HandleBinFile("$short/Root Entry/Nets6/Data.dat","",0,0, sub 
  { 
  });


  HandleBinFile("$short/Root Entry/Arcs6/Data.dat","\x01",0,0,sub 
  { 
    my $fn=$_[0]{'NAME'};
    my $value=$_[1];
  	my $x=unpack("l",substr($value,13,4))/$faktor/10000-$xmove;
	my $y=unpack("l",substr($value,17,4))/$faktor/10000;$y=$ymove-$y;
	my $width=unpack("l",substr($value,21,4))/$faktor/10000;
	my $layer=$layermap{unpack("C",substr($value,0,1))} || "F.Cu";
	#print "layer:$layer x:$x y:$y width:$width\n";
	#my $layer2=$layermap{unpack("C",substr($value,1,1))} || "B.Cu";

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
  	my $x=unpack("l",substr($value,13,4))/$faktor/10000-$xmove;
	my $y=unpack("l",substr($value,17,4))/$faktor/10000;$y=$ymove-$y;
	my $width=unpack("l",substr($value,21,4))/$faktor/10000;
	my $layer1=$layermap{unpack("C",substr($value,0,1))} || "F.Cu";
	my $layer2=$layermap{unpack("C",substr($value,1,1))} || "B.Cu";
	#print "Layer: $layer1 -> $layer2\n";
	print "Unknown layer: ".unpack("C",substr($value,0,1))."\n" if(!defined($layermap{unpack("C",substr($value,0,1))}));
#	print "Unknown layer: ".unpack("C",substr($value,1,1))."\n" if(!defined($layermap{unpack("C",substr($value,1,1))}));

	#print "Koordinaten:\n" if($debug);
	#print "x:$x y:$y width:$width\n" if($debug);
	print OUT "  (via (at $x $y) (size $width) (layers $layer1 $layer2) (net 0))\n";
	
	if(0) # $count>19000 && !($count%50))
	{
	  #print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 0))\n";	  
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
 	      #print "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer B.Paste) (net 0))\n";
     	  #print OUT "  (segment (start $x1 $y1) (end $x1 2000) (width $width) (layer B.Paste) (net 0))\n";
	      #print OUT "  (segment (start $x2 $y2) (end $x2 2000) (width $width) (layer B.Paste) (net 0))\n";
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
	my $width=$d{'TRACKWIDTH'}||1;$width=~s/mil$//; #/$faktor/10000;
	my $layer=$layermap{$d{'LAYER'}} || "F.Paste";
	print "NOT FOUND: ".$d{'LAYER'}."\n" if(!defined($layermap{$d{'LAYER'}}));
	my $maxpoints=0;
	foreach(keys %d)
	{
	  if(m/^SA(\d+)/)
	  {
	    $maxpoints=$1 if($1>$maxpoints);
      }
	}
	foreach(0 .. $maxpoints-2)
	{
	  my $sx=$d{'VX'.$_};$sx=~s/mil$//;$sx/=$faktor;$sx-=$xmove;
	  my $sy=$d{'VY'.$_};$sy=~s/mil$//;$sy/=$faktor;$sy=$ymove-$sy;
	  my $ex=$d{'VX'.($_+1)};$ex=~s/mil$//;$ex/=$faktor;$ex-=$xmove;
	  my $ey=$d{'VY'.($_+1)};$ey=~s/mil$//;$ey/=$faktor;$ey=$ymove-$ey;
	  print OUT "(gr_line (start $sx $sy) (end $ex $ey) (angle 90) (layer $layer) (width 0.2))\n";
	}
   });
  

  HandleBinFile("$short/Root Entry/Tracks6/Data.dat","\x04",0,0, sub 
  { 
    my $value=$_[1];
    my $x1=unpack("l",substr($value,13,4))/$faktor/10000-$xmove;
	my $y1=unpack("l",substr($value,17,4))/$faktor/10000;$y1=$ymove-$y1;
	my $x2=unpack("l",substr($value,21,4))/$faktor/10000-$xmove;
	my $y2=unpack("l",substr($value,25,4))/$faktor/10000;$y2=$ymove-$y2;
	my $width=unpack("l",substr($value,29,4))/$faktor/10000;
	my $layer=$layermap{unpack("C",substr($value,0,1))} || "Cmts.User";
	#print "Koordinaten:\n";
	#print "x:$x y:$y\n";
	print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 0))\n";
	if(0) # $count>19000 && !($count%50))
	{
	  #print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net 0))\n";
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
 	      #print "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer B.Paste) (net 0))\n";
     	  #print OUT "  (segment (start $x1 $y1) (end $x1 2000) (width $width) (layer B.Paste) (net 0))\n";
	      #print OUT "  (segment (start $x2 $y2) (end $x2 2000) (width $width) (layer B.Paste) (net 0))\n";
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


  #HandleBinFile("$short/Root Entry/Pads6/Data.dat","\x02",0,0, sub 
  {
    my $value=readfile("$short/Root Entry/Pads6/Data.dat");
	$value=~s/\r\n/\n/gs;
	open AOUT,">$short/Root Entry/Pads6/Data.dat.txt";
	my $pos=0;
	while($pos<length($value))
	{
	  my $len=unpack("l",substr($value,$pos+1,4));
	  print AOUT bin2hex(substr($value,$pos,5))." ";
	  print AOUT sprintf("%10s",bin2hex(substr($value,$pos+5,$len)))." ";
	  $pos+=5+$len;
	  
      my $x1=unpack("l",substr($value,$pos+36,4))/$faktor/10000-$xmove;
	  my $y1=unpack("l",substr($value,$pos+40,4))/$faktor/10000;$y1=$ymove-$y1;
	  	  
	  print AOUT bin2hex(substr($value,$pos,143))." ";
	  my $len2=unpack("l",substr($value,$pos+143,4));
	  $pos+=147;
  	  print AOUT bin2hex(substr($value,$pos,$len2))."\n";
      $pos+=$len2;
	  
	  my $width=0.5;
	  
 	  print OUT <<EOF
 (gr_text "PAD" (at $x1 $y1) (layer F.Cu)
    (effects (font (size $width $width) (thickness 0.1)))
  )
EOF
;

	  
	}
    close AOUT;
  
  }#);
  
	
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
	my $layer=$layermap{unpack("C",substr($value,0,1))} || "Cmts.User";
    my $x1=unpack("l",substr($value,13,4))/$faktor/10000-$xmove;
	my $y1=unpack("l",substr($value,17,4))/$faktor/10000;$y1=$ymove-$y1;
	my $x2=unpack("l",substr($value,21,4))/$faktor/10000-$xmove;
	my $y2=unpack("l",substr($value,25,4))/$faktor/10000;$y2=$ymove-$y2;
	#print "Koordinaten:\n";
	#print "x:$x y:$y\n";
	print OUT <<EOF
	  (zone (net 0) (net_name "") (layer $layer) (tstamp 53EB93DD) (hatch edge 0.508)
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
	my $layer=$layermap{$d{'V7_LAYER'}};
	print "Please define mapping for layer $d{V7_LAYER}\n" if(!defined($layer));
	#print "Layer: $layer\n";
	
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
	#my $layer=$layermap{$d{'V7_LAYER'}};
	#print "Please define mapping for layer $d{V7_LAYER}\n" if(!defined($layer));
	#print "Layer: $layer\n";
	my $datalen=(unpack("l",substr($value,22+$textlen,4))+1)*37;
	my $data=substr($value,22+$textlen+4,$datalen);
	foreach(0 .. unpack("l",substr($value,22+$textlen,4))-1)
	{
      my $x1=unpack("l",substr($data,$_*37+1,4))/$faktor/10000-$xmove;
	  my $y1=unpack("l",substr($data,$_*37+5,4))/$faktor/10000;$y1=$ymove-$y1;
      my $x2=unpack("l",substr($data,$_*37+37+1,4))/$faktor/10000-$xmove;
	  my $y2=unpack("l",substr($data,$_*37+37+5,4))/$faktor/10000;$y2=$ymove-$y2;
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
      my $layer=$layermap{unpack("C",substr($content,$pos,1))} || "Cmts.User";
	  my $x1=unpack("l",substr($content,$pos+13,4))/$faktor/10000-$xmove;
	  my $y1=unpack("l",substr($content,$pos+17,4))/$faktor/10000;$y1=$ymove-$y1;
      my $width=unpack("l",substr($content,$pos+21,4))/$faktor/10000;
	  my $dir=unpack("d",substr($content,$pos+27,8)); 
	  my $font=substr($content,$pos,$fontlen); $pos+=$fontlen;
	  my $fontname=ucs2utf(substr($font,46,64));
      my $textlen=unpack("l",substr($content,$pos,4)); $pos+=4;
	  my $text=substr($content,$pos+1,$textlen-1); $pos+=$textlen;
	  #print  bin2hex($font)." $fontname"."   $text $dir\n";
	  $text=~s/"/''/g;
	  print OUT <<EOF
 (gr_text "$text" (at $x1 $y1 $dir) (layer $layer)
    (effects (font (size $width $width) (thickness 0.1)))
  )
EOF
;
	}
  } 
  
  print OUT ")\n";
}

