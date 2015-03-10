#!/usr/bin/perl -w
use strict;
use Compress::Zlib;
use Math::Geometry::Planar;
use Data::Dumper;
use Cwd;
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
# Rounded Rectangles (Not just ovals that are circles when they are even sided
# Novena had too many netclasses for KiCad <BZR 5406, the NetClass editor in the Design Rules Editor vanished due to GUI layout when there are too many netclasses: https://bugs.launchpad.net/kicad/+bug/1418135
# Loading the 3D viewer is slow, especially when the zones are filled. It only utilizes a single core.
# The 3D view currently has a problem with relative pathes: https://bugs.launchpad.net/kicad/+bug/1417786  a workaround is available with the $absoluteWRLpath option

# Things that are missing in Altium:
# The Zone-Fill-Polygons are not saved in the file. Workaround: Press "b" in PcbNew or: select the zone tool, right-click on an empty area, then "Fill all zones"
# Annotations in the fileformat

# Todos for this converter:
# Wrong recordtype errors for Regions6
# Correct positioning for Cones, Cylinders, ... 


my $annotate=1;

my $absoluteWRLpath=1;

my $wrlprefix=$absoluteWRLpath ? Cwd::cwd() : ".";

my $current_status=<<EOF
Advanced Placer Options6 # Not needed
Arcs6 # Likely Done
Board6 # Here are various global infos about the whole board and about the layers
BoardRegions # Here we likely have only 1 region for Novena. Keepouts are defined here. KiCad does not have a Region concept yet.
Classes6 # NetClasses and ComponentClasses
ComponentBodies6 # Nearly Done
Components6 # Nearly Done
Connections6 # Empty
Coordinates6 # Empty
Design Rule Checker Options6 # To be done later
DifferentialPairs6 # To be done later
Dimensions6 # Annotations about the dimensions
EmbeddedBoards6 # Empty
EmbeddedFonts6 # 2 Fonts, we don´t need them
Embeddeds6 # Empty
ExtendedPrimitiveInformation # Empty
FileVersionInfo # Messages for when the file is opened in older Altium versions that do not support certain features in this fileformat
Fills6 # Needs to be verified, are they really rectangular? 
FromTos6 # Empty
Models # Done
ModelsNoEmbed # Empty
Nets6 # Needed
Pads6 # Important
Pin Swap Options6 # Only 1 line, likely not needed
Polygons6 # Done
Regions6 #
Rules6 #
ShapeBasedComponentBodies6 # HALF-Done, do we need more?
ShapeBasedRegions6 # Not needed, I guess
SmartUnions # Empty
Texts # Warnings for older Altium versions, I think we don´t need to support those ;-)
Texts6 # Partly done, NEEDED
Textures # Empty
Tracks6 # Done
Vias6 # Done
WideStrings6 # Seems to be a copy of Texts6, just for Unicode?!?
EOF
;

my $pi=3.14159265359;
my $faktor=39.370078740158;
my $fak="0.39370078740158";

sub mil2mm($)
{
  return undef unless(defined($_[0]));
  my $data=$_[0];
  $data=~s/mil$//;
  $data/=$faktor;
  return sprintf("%.6f",$data); 
}
sub bmil2mm($)
{
  return sprintf("%.7f",unpack("l",$_[0])/$faktor/10000);
}


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

# This function converts a binary string to its hex representation for debugging
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

# This function returns, whether 2 values are near each other
sub near($$)
{
  my $d=0.01;
  return ($_[0]>$_[1]-$d && $_[0]<$_[1]+$d);
}

sub near2d($$$$)
{
  my $d=0.0001;
  return (sqrt(($_[0]-$_[1])*($_[0]-$_[1])+($_[2]-$_[3])*($_[2]-$_[3]))<$d);
}


# This is the main handling function that parses most of the binary files inside a .PcbDoc
sub HandleBinFile 
{
  my ($filename,$recordtype,$headerlen,$nskip,$piped)=@_;
  # filename is the filename of the file to load
  # recordtype is a string that is checked at the beginning of every record, after the header
  # headerlen is the length of the header to read and have as callback parameter $_[2] at the beginning of each record
  # nskip
  # piped is a callback function that gets called with the parameters $piped->(\%d,$data,$header,$line);
  my $model=1;
  my $content=readfile($filename);

  return unless defined($content);
  $content=~s/\x0d\x0a/\x0a/gs;
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
	if($rtyp ne $recordtype)
	{
	  print "Error: Wrong recordtype: $rtyp, expected $recordtype\n";
	  last;
	}
	$pos+=length($recordtype);
	
	print HBOUT sprintf("Pos: %08X ",$pos);
    my $len=sprintf("%.5f",unpack("l",substr($content,$pos,4))); 
	$len-- if($len==0x59917); #  Workaround for Regions6  !!! TODO  XXX  Perhaps it is a CRLF issue?
	$pos+=4;
    print HBOUT sprintf("len: %08X ",$len);
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

sub Box($$$$$$$$)
{
  my ($translation,$rotation,$scale,$color,$shininess,$sx,$sy,$sz)=@_;

 # Box("1 1 1","0 0 1  0","1 1 1","0.598039217 0.098039217 0.098039217","1","1","1","1");
  
  return <<EOF
Transform
{
  translation $translation
  rotation $rotation
  scale $scale
  scaleOrientation 0 0 1  0
  center 0 1 0
  children 
    Shape 
	{
      appearance 
        Appearance 
		{
          material 
            Material 
			{
              diffuseColor $color
              shininess $shininess
            }
        }
      geometry 
        IndexedFaceSet
		{
          coord 
            Coordinate 
			{
              point [ 0   0   0,
                      0   0   $sz,
                      0   $sy $sz,
                      0   $sy 0,
                      $sx 0   0,
                      $sx 0   $sz,
                      $sx $sy $sz,
                      $sx $sy 0					  
					]
            }                              
            coordIndex [ 3, 1, 2, -1, 0, 1, 3, -1,
                         5, 7, 6, -1, 5, 4, 7, -1,
                         4, 5, 0, -1, 0, 5, 1, -1,
                         6, 7, 3, -1, 6, 3, 2, -1,
                         3, 7, 0, -1, 0, 7, 4, -1,
                         6, 2, 1, -1, 6, 1, 5, -1 ]
          ccw TRUE
          solid FALSE
          convex TRUE
        }

    }
}
EOF
;
}


sub ExtrudedPolygon($$$$$$$)
{
  my ($translation,$rotation,$scale,$color,$shininess,$height,$polygon)=@_;

  my @points=@{$polygon};
  my $count=0;
  my $n=scalar(@points);

  my @polyarray=();  
  
  my @point=();
  my @line=();
  foreach(0 .. $n-1)
  {
    push @point,$points[$_]." 0",$points[$_]." $height";
	#push @line,$_*2,(($_+1)%$n)*2,(($_+2)%$n)*2,-1;
	push @line,$_*2,$_*2+1,(($_+1)%$n)*2,-1; # Side
	push @line,(($_+1)%$n)*2,$_*2+1,(($_+1)%$n)*2+1,-1; # Side
	push @polyarray,[$1,$2] if($points[$_]=~m/^(-?\d+\.?\d*)\s+(-?\d+\.?\d*)$/ && ($points[$_] ne $points[($_+1)%$n]));
  }

  #print Dumper(\@polyarray);
  
  my $poly = Math::Geometry::Planar->new;
  $poly->points(\@polyarray);
  my @triangles=$poly->triangulate();
  
  my $pos=$n*2;
  #print Dumper(\@triangles);
  #push @line,-1,-1,-1,-1;
  foreach(@triangles)
  {
	#Bottom:
    push @point,"$_->{points}[0][0] $_->{points}[0][1] 0\n","$_->{points}[1][0] $_->{points}[1][1] 0","$_->{points}[2][0] $_->{points}[2][1] 0";
    push @line,$pos,$pos+2,$pos+1,-1;

	#Top:
    push @point,"$_->{points}[0][0] $_->{points}[0][1] $height\n","$_->{points}[1][0] $_->{points}[1][1] $height","$_->{points}[2][0] $_->{points}[2][1] $height";
    push @line,$pos+3,$pos+4,$pos+5,-1;

	$pos+=6;
  }
  #exit;
  
  my $points=join ",",@point;
  my $lines=join ",",@line;  
  
  return <<EOF
Transform
{
  translation $translation
  rotation $rotation
  scale $scale
  scaleOrientation 0 0 1  0
  center 0 1 0
  children 
    Shape 
	{
      appearance 
        Appearance 
		{
          material 
            Material 
			{
              diffuseColor $color
              shininess $shininess
            }
        }
      geometry 
        IndexedFaceSet
		{
          coord 
            Coordinate 
			{
              point [ $points ]
            }                              
            coordIndex [ $lines ]
          ccw TRUE
          solid FALSE
          convex TRUE
        }

    }
}
EOF
;
}



sub Cylinder($$$$$$$)
{
  my ($translation,$rotation,$scale,$color,$shininess,$r,$h)=@_;
  
  my $parts=32;
  
  my @point=();
  my @line=();
 
  # Middle bottom point
  push @point,"0 0 0";
  
  # Middle top point
  push @point,"0 0 $h";
  
  foreach (0 .. $parts-1)
  {
    push @point,"".sprintf("%.7f",(sin($_*2*$pi/$parts)*$r))." ".sprintf("%.7f",(cos($_*2*$pi/$parts)*$r))." 0";
    push @point,"".sprintf("%.7f",(sin($_*2*$pi/$parts)*$r))." ".sprintf("%.7f",(cos($_*2*$pi/$parts)*$r))." $h";
	push @line,$_*2+2,(($_+1)%$parts)*2+2,0,-1; # Bottom
	push @line,$_*2+3,(($_+1)%$parts)*2+3,1,-1; # Top
	push @line,$_*2+2, $_*2+3, (($_+1)%$parts)*2+2,-1; # Side
	push @line,$_*2+3,(($_+1)%$parts)*2+3,  (($_+1)%$parts)*2+2,-1; # Side
	
  }
  my $points=join ",",@point;
  my $lines=join ",",@line;  
 
  return <<EOF
Transform
{
  translation $translation
  rotation $rotation
  scale $scale
  scaleOrientation 0 0 1  0
  center 0 1 0
  children 
    Shape 
	{
      appearance 
        Appearance 
		{
          material 
            Material 
			{
              diffuseColor $color
              shininess $shininess
            }
        }
      geometry 
        IndexedFaceSet
		{
          coord 
            Coordinate 
			{
              point [ $points ]
            }                              
            coordIndex [ $lines ]
          ccw TRUE
          solid FALSE
          convex TRUE
        }

    }
}
EOF
;
}

sub Cone($$$$$$$)
{
  my ($translation,$rotation,$scale,$color,$shininess,$r,$h)=@_;
  
  my $parts=32;
  
  my @point=();
  my @line=();
 
  # Middle point
  push @point,"0 0 0";
  
  # Top point
  push @point,"0 0 $h";
  
  foreach (0 .. $parts-1)
  {
    push @point,"".sprintf("%.7f",(sin($_*2*$pi/$parts)*$r))." ".sprintf("%.7f",(cos($_*2*$pi/$parts)*$r))." 0";
	push @line,$_+2,0,(($_+1)%$parts)+2,-1;
	push @line,$_+2,1,(($_+1)%$parts)+2,-1;
  }
  my $points=join ",",@point;
  my $lines=join ",",@line;  
 
  return <<EOF
Transform
{
  translation $translation
  rotation $rotation
  scale $scale
  scaleOrientation 0 0 1  0
  center 0 1 0
  children 
    Shape 
	{
      appearance 
        Appearance 
		{
          material 
            Material 
			{
              diffuseColor $color
              shininess $shininess
            }
        }
      geometry 
        IndexedFaceSet
		{
          coord 
            Coordinate 
			{
              point [ $points ]
            }                              
            coordIndex [ $lines ]
          ccw TRUE
          solid FALSE
          convex TRUE
        }

    }
}
EOF
;
}



# This marks a specific point for debugging and adds additionial lines around the point that look like a star
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


# At first we read the curated Altium->KiCad standard component mappings:
my %modelhints=();
my %originalhints=();
foreach my $mod(glob('"pretty.pretty/*"'))
{
  my $content=readfile($mod);
  if($content=~m/\(model ([.\w\/\-]*)\s*(.*)/s)
  {
    my($model,$value)=($1,$2);
	$value=~s/\)\s*$//s;
	if(defined($modelhints{$model}))
	{
	  print "Error: Redefining model for model $model hints in file $mod from file $originalhints{$model}.\nPlease delete one of the files\n";
	  exit;
	}
    $modelhints{$model}=$value;
	$originalhints{$model}=$mod;
	#print "\n*$model* =>\n----------\n$value\n------------\n";
  }
  
}


my $trackwidth=10;

# Now we start handling all the PCB files that were unpacked by unpack.pl already:
my $filecounter=0;
foreach my $filename(glob('"*/Root Entry/Board6/Data.dat"'))
{
  $filecounter++;
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
  my %activelayer=();
  my %layernext=();
  my %layerprev=();
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
	  if($_=~m/^LAYER(\d+)NEXT$/)
	  {
	    $layernext{$1}=$d{$_};
		$activelayer{$1}=1 if($d{$_});
		#print "$1 -> $d{$_}\n";
	  }
      if($_=~m/^LAYER(\d+)PREV$/)
	  {
	    $layerprev{$1}=$d{$_};
		$activelayer{$1}=1 if($d{$_});
		#print "$1 -> $d{$_}\n";
	  }
	  if($_=~m/^TRACKWIDTH$/)
	  {
	    print "Track Width: $d{$_}\n";
		$trackwidth=$d{$_};
	  }
	}
  }); # Board
  
  my $firstlayer=0;
  my $lastlayer=0;
  my @layersorder=();
  foreach(keys %activelayer)
  {
    $firstlayer=$_ if($layerprev{$_}==0 && $layernext{$_}!=0);
	$lastlayer=$_ if($layerprev{$_}!=0 && $layernext{$_}==0);
  }
  
  my $thislayer=$firstlayer;
  while($thislayer!=0)
  {
	push @layersorder,$thislayer;
	$thislayer=$layernext{$thislayer};
  }
  #print "Layers: ".join(",",@layersorder)."\n";
  
  #print "Active layers: ".scalar(keys %activelayer)."\n";
    

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
  our %componentbodyavailable=();  
  
  our %nameon=();
  our %commenton=();
   
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

  our %rules=();
  HandleBinFile("$short/Root Entry/Rules6/Data.dat","",2,0,sub 
  {
    my $rulekind=$_[0]{'RULEKIND'};
	my $name=$_[0]{'NAME'};
    my $clearance=mil2mm($_[0]{'CLEARANCE'});
	my $gap=mil2mm($_[0]{'GAP'});
	my $airgap=mil2mm($_[0]{'AIRGAPWIDTH'});
	my $conductorwidth=mil2mm($_[0]{'RELIEFCONDUCTORWIDTH'});
	if(defined($clearance))
	{
	  print "Rule $rulekind $name gives clearance $clearance\n";
	  $rules{$name}=$clearance;
	}
	if(defined($gap))
	{
	  print "Rule $rulekind $name gives gap $gap\n";
	  $rules{$name}=$gap;
	}
	if(defined($airgap))
    {
	  $rules{$name.".AIRGAP"}=$airgap;
	}
	if(defined($conductorwidth))
    {
	  $rules{$name.".RELIEFCONDUCTORWIDTH"}=$conductorwidth;
	}
  });
  
  our %netclass=();
  our %netclassrev=();
  HandleBinFile("$short/Root Entry/Classes6/Data.dat","",0,0,sub 
  {
    my $name=$_[0]{'NAME'};
	my $superclass=$_[0]{'SUPERCLASS'};
    my $kind=$_[0]{'KIND'};
	#KIND={0,1,2,3,4,6,7}
    #0: Net-Classes
    #1: Source-Schematic-Sheet-Classes (Hierarchical Schematics)
    #2: All From-Tos (?)
    #3: Pad-Classes
    #4: Layer-Classes
    #5: ?
    #6: Differential Pair-Classes
    #7: Polygon-Classes
    if($superclass eq "FALSE" && $kind==0)
	{
	  foreach my $key(keys %{$_[0]})
	  {
	    if($key=~m/^M(\d+)$/)
		{
		  $netclass{$name}{$_[0]{$key}}=1;
		  $netclassrev{$_[0]{$key}}=$name;
		}
	  }
	}
  });

  print "Writing PCB to $short.kicad_pcb\n";
  open OUT,">$short.kicad_pcb";

  our $nets="";
  our $nnets=2;
  our %netnames=("1"=>"Net1");
  HandleBinFile("$short/Root Entry/Nets6/Data.dat","",0,0, sub 
  { 
    my $line=$_[3]+2;
	$nnets=$line+1;
    my $name=$_[0]{'NAME'};
	$netnames{$line}=$name;
    $nets.= "  (net $line \"$name\")\n";
  });


  my $clearance=$rules{'Clearance'} || "0.127";
  my $tracewidth=mil2mm($trackwidth);

  my $layertext="";
  foreach(1 .. scalar(@layersorder)-2)
  {
     $layertext.="	($_ In$_.Cu signal)\n";
  } 
  
  
  # This is the standard Header for the .kicad_pcb file
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
    (nets $nnets)
  )

  (page A4)
  (layers
    (0 F.Cu signal)
$layertext
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
    (trace_clearance 0.127)
    (zone_clearance 0.0144)
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
$nets
  
  (net_class Default "This is the default net class."
    (clearance $clearance)
    (trace_width $tracewidth)
    (via_dia 0.889)
    (via_drill 0.635)
    (uvia_dia 0.508)
    (uvia_drill 0.127)
	(add_net Net1)
  )
  
EOF
;
  foreach my $class(sort keys %netclass)
  {
    print OUT " (net_class $class \"$class\"\n";
	print OUT <<EOF
	(clearance $clearance)
    (trace_width $tracewidth)
    (via_dia 0.889)
    (via_drill 0.635)
    (uvia_dia 0.508)
    (uvia_drill 0.127)
EOF
;
    print OUT "    (add_net \"$_\")\n" foreach(sort keys %{$netclass{$class}});
    print OUT "  )\n";
  }


  
  my $xmove=95.3; 
  my $ymove=79.6; 
  #$xmove=50;$ymove=250; # Enable to move Novena mainboard into the frame, or disable to move it to align to the Gerber-Imports
  $xmove=0; $ymove=0; # Enable to align GPBB to the Gerber Imports
  
  my %layermap=(
  "1"=>"F.Cu",
  "2"=>"In4.Cu", # ???  Signal Layer 2/Mid
  "3"=>"In2.Cu",
  "4"=>"In3.Cu",
  "6"=>"In5.Cu",
  "11"=>"In6.Cu",
  "12"=>"In7.Cu",
  "32"=>"B.Cu",
  "33"=>"F.SilkS",
  "34"=>"B.SilkS",
  "35"=>"F.Paste",
  "36"=>"B.Paste",
  "37"=>"F.Mask",
  "38"=>"B.Mask",
  "39"=>"In1.Cu",
  "40"=>"In4.Cu",
  "41"=>"In5.Cu",
  "42"=>"In8.Cu",
  "44"=>"In6.Cu",
  "56"=>"Edge.Cuts",
  "57"=>"Edge.Cuts",
  "58"=>"Dwgs.User",
  "59"=>"Dwgs.User",
  "60"=>"In4.Cu",
  "61"=>"In5.Cu",
  "62"=>"In6.Cu",
  "63"=>"In7.Cu",
  "64"=>"In8.Cu",
  "65"=>"In9.Cu",
  "66"=>"In10.Cu",
  "67"=>"In11.Cu",
  "68"=>"In12.Cu",
  "69"=>"Dwgs.User",
  "70"=>"B.Cu",
  "71"=>"F.CrtYd",
  "72"=>"B.CrtYd",
  "73"=>"Eco2.User",
  "74"=>"Dwgs.User",
  );
  
  foreach(1 .. scalar(@layersorder)-2)
  {
     if($layermap{$layersorder[$_]} ne "In$_.Cu")
	 {
	   #print "Changing $_ $layersorder[$_] from old value $layermap{$layersorder[$_]} to In$_.Cu\n";
	 }
     $layermap{$layersorder[$_]}="In$_.Cu";
  }
  
  
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
  $layermap{"BOTTOMOVERLAY"}=$layermap{34};
  $layermap{"TOPSOLDER"}=$layermap{37};
  $layermap{"BOTTOMSOLDER"}=$layermap{38};
  $layermap{"TOPPASTE"}=$layermap{35};
  $layermap{"BOTTOMPASTE"}=$layermap{36};
  $layermap{"MULTILAYER"}=$layermap{74};
  $layermap{"MECHANICAL14"}=$layermap{70};
 
  foreach(sort keys %layermap)
  {
    #print "SORT: $_ -> $layermap{$_}\n";
  }
 
  my %pads=();
  our %unmappedLayers=();
  our %usedlayers=();
  our %layererrors=();
  
  # This function maps the Layer numbers or names to KiCad Layernames
  sub mapLayer($)
  {
    my $lay=$_[0];
	if(!defined($lay))
	{
	  print "mapLayer called with undefined layername\n";
	  return undef;
	}
	$usedlayers{$lay}++;
    if(!defined($layermap{$lay}))
	{
	  my $name="Eco1.User"; $name=$1 if($layerdoku=~m/name: *$lay *([\w.]+)/);
      $unmappedLayers{$_[0]}=$name ;
	}
	if(!defined($layermap{$_[0]}) && !defined($layererrors{$_[0]}))
	{
      print "No mapping for Layer ".$_[0]." defined!\n" ;
	  $layererrors{$_[0]}=1;
	}
	return $layermap{$_[0]}; 
  }

  #Mapping the Standard components to KiCad Standard Components:
  our %A2Kwrl=(
    "Chip Diode - 2 Contacts.PcbLib/CD1608-0603"=>"smd/Capacitors/C0603.wrl",
    "Chip Diode - 2 Contacts.PcbLib/CD2012-0805"=>"smd/Capacitors/C0805.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC1005N"=>"smd/Capacitors/C0402.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC1608N"=>"smd/Capacitors/C0603.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC2012N"=>"smd/Capacitors/C0805.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC3216N"=>"smd/Capacitors/C1206.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC3225N"=>"smd/Capacitors/C1210.wrl",
    "Chip_Resistor_N.PcbLib/RESC1005N"=>"smd/resistors/R0402.wrl",
    "Chip_Resistor_N.PcbLib/RESC1608N"=>"smd/resistors/R0603.wrl",
    "Chip_Resistor_N.PcbLib/RESC2012N"=>"smd/resistors/R0805.wrl",
    "Chip_Resistor_N.PcbLib/RESC3216N"=>"smd/resistors/R1206.wrl",
    "Miscellaneous Connectors.IntLib/HDR2X20"=>"Pin_Headers/Pin_Header_Straight_2x20.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X4"=>"Pin_Headers/Pin_Header_Straight_1x4.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X6"=>"Pin_Headers/Pin_Header_Straight_1x6.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X8"=>"Pin_Headers/Pin_Header_Straight_1x8.wrl",  
    "Miscellaneous Connectors.IntLib/HDR2X8"=>"Pin_Headers/Pin_Header_Straight_2x8.wrl",
    "NSC LDO.IntLib/MP04A_N"=>"smd/SOT223.wrl",
    "National Semiconductor DAC.IntLib/MUA08A_N"=>"smd/smd_dil/msoic-8.wrl",
    "SOIC_127P_N.PcbLib/SOIC127P600-8N"=>"smd/smd_dil/psop-8.wrl",
    "SOP_65P_N.PcbLib/SOP65P640-16N"=>"smd/smd_dil/ssop-16.wrl",
    "SOT23_5-6Lead_N.PcbLib/SOT23-5AN"=>"smd/SOT23_5.wrl",
    "TSOP_65P_N.PcbLib/TSOP65P640-24AN"=>"smd/smd_dil/tssop-24.wrl",
    "commonpcb.lib/CAPC0603N_B"=>"smd/Capacitors/C0603.wrl",
    "commonpcb.lib/CAPC1608N_HD"=>"smd/Capacitors/C1608.wrl",
    "commonpcb.lib/SWITCH_TS-1187A"=>"Pin_Headers/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/USB_TYPEA_TH_SINGLE"=>"Pin_Headers/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/HAOYU_TS_1185A_E"=>"Pin_Headers/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/JST_S3B_EH"=>"Pin_Headers/Pin_Header_Straight_1x3.wrl",
	);
		
  our $componentid=0;
  our %componentatx=();
  our %componentaty=();
  our %componentlayer=();
  our %kicadwrl=();
  our %kicadwrlerror=();
  
  HandleBinFile("$short/Root Entry/Components6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	my $atx=mil2mm($d{'X'});$atx-=$xmove;
	$componentatx{$componentid}=$atx;
	#print "\$componentatx{$componentid}=$atx\n";
	my $aty=mil2mm($d{'Y'});$aty=$ymove-$aty;
	$componentaty{$componentid}=$aty;
    $componentlayer{$componentid}=$d{'LAYER'};
	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'PATTERN'};
#	my $reference=$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'};
	my $newreference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'PATTERN'};
	
	$kicadwrl{$componentid}=$A2Kwrl{$reference};
	
	$nameon{$componentid}=$d{'NAMEON'};
	$commenton{$componentid}=$d{'COMMENTON'};
	
	
	if(defined($kicadwrl{$componentid}))
	{
	  #$newa2k{" \"$newreference\"=>\"".$A2Kwrl{$reference}."\",\n"}=1;
	}
	else
	{
	  #print "    \"$reference\"=>\".wrl\",\n" if(!defined($kicadwrlerror{$reference}));
	  $kicadwrlerror{$reference}=1;
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
	while($pos+140<length($value))
	{
	  my $len=sprintf("%.5f",unpack("l",substr($value,$pos+1,4)));
	  print AOUT bin2hex(substr($value,$pos,5))." ";
	  print AOUT sprintf("A:%10s",bin2hex(substr($value,$pos+5,$len)))." ";
	  my $name=substr($value,$pos+6,$len-1);
	  $pos+=5+$len;

      my $component=unpack("s",substr($value,$pos+30,2));	

	  #print AOUT "component:$component net:$net\n";
      my $x1=-$xmove+bmil2mm(substr($value,$pos+36,4));
	  my $y1=$ymove-bmil2mm(substr($value,$pos+40,4));
  	  #MarkPoint($x1,$y1) if($counter eq 2);
	  $x1-=$componentatx{$component} if($component>=0 && defined($componentatx{$component}));
	  $y1-=$componentaty{$component} if($component>=0 && defined($componentaty{$component}));

      $x1=sprintf("%.5f",$x1);
	  $y1=sprintf("%.5f",$y1);
	  
      my $altlayer=unpack("C",substr($value,$pos+23,1));
      my $layer=mapLayer($altlayer) || "F.Cu"; $layer="F.Cu B.Cu" if($altlayer==74);
	  
	  $layer.=" F.Mask F.Paste" if($layer=~m/F\.Cu/);
	  $layer.=" B.Mask B.Paste" if($layer=~m/B\.Cu/);

	  my $sx=bmil2mm(substr($value,$pos+44,4));
	  my $sy=bmil2mm(substr($value,$pos+48,4));
	  my $holesize=bmil2mm(substr($value,$pos+68,4));

	  
	  my $dir=unpack("d",substr($value,$pos+75,8)); 
	  
	  my $mdir=($dir==0)?"":" $dir";
	  
	  my %typemap=("2"=>"rect","1"=>"circle");
      my $type=$typemap{unpack("C",substr($value,$pos+72,1))};	  
	  
	  $type="oval" if($type eq "circle" && $sx != $sy);
	  
      my %platemap=("0"=>"FALSE","1"=>"TRUE");
      my $plated=$platemap{unpack("C",substr($value,$pos+83,1))};	  

	  
      my $net=unpack("s",substr($value,$pos+26,2))+2;	  
	  my $netname=$netnames{$net};
	  
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
 	  my $nettext=($net>1)?"(net $net \"$netname\")":"";

	  $pads{$component}.=<<EOF
#1309
    (pad "$name" $tp $type (at $x1 $y1$mdir) (size $sx $sy) $drill
      (layers $layer) $nettext
    )
EOF
;
	  
	  $counter++;
	  
	}
    close AOUT;
  
  }#);


  HandleBinFile("$short/Root Entry/ComponentBodies6/Data.dat","",23,16, sub 
  { 
    print OUT "#ComponentBodies#".$_[3].": ".bin2hex($_[2])." ".$_[1]."\n" if($annotate);

    my %d=%{$_[0]};
	my $header=$_[2];
	my $component=unpack("s",substr($header,12,2));
	print OUT "#\$pads{$component}\n" if($annotate);
	#print "Component:$component\n";
	my $id=$d{'MODELID'};
	my $atx=mil2mm($d{'MODEL.2D.X'});$atx-=$xmove;
	my $aty=mil2mm($d{'MODEL.2D.Y'});$aty=$ymove-$aty;
	my $layer=defined($d{'V7_LAYER'})?($d{'V7_LAYER'} eq "MECHANICAL1"?"B.Cu":"F.Cu"):"F.Cu";
	
	my $catx=$componentatx{$component};

	my $stp=defined($modelname{$id})?$modelname{$id}:undef; # $d{'IDENTIFIER'}."_". $stp=~s/\{//; $stp=~s/\}//; $stp=$d{'BODYPROJECTION'}; #substr($text,0,10);
	print OUT <<EOF
  (gr_text "$stp" (at $atx $aty) (layer $layer)
    (effects (font (size 1.0 1.0) (thickness 0.2)) )
  )
EOF
if(0 && defined($stp)); 
	
	
    $atx-=$componentatx{$component} if($component>=0 && defined($componentatx{$component}));
	$aty-=$componentaty{$component} if($component>=0 && defined($componentaty{$component}));
	
	$atx=sprintf("%.5f",$atx);
	$aty=sprintf("%.5f",$aty);
	
	#print $d{'MODELID'}."\n";
	if(!defined($modelname{$d{'MODELID'}}))
	{
	  #print "MODELID: $d{'MODELID'}\n";
	}


	my $ident=""; $ident.=pack("C",$_) foreach(split(",",$d{'IDENTIFIER'}));
	
	#my $rot=(($modelrotx{$id}||0)+$d{'MODEL.3D.ROTX'})." ".(($modelroty{$id}||0)+$d{'MODEL.3D.ROTY'})." ".(($modelrotz{$id}||0)+$d{'MODEL.3D.ROTZ'});
	my $rot=((360-$d{'MODEL.3D.ROTX'})." ".(360-$d{'MODEL.3D.ROTY'})." ".(360-$d{'MODEL.3D.ROTZ'}));
	#my $rot=(($modelrotx{$id}||0))." ".(($modelroty{$id}||0))." ".(($modelrotz{$id}||0));
	my $mdz=mil2mm($modeldz{$id}||0);
	#my $dz=mil2mm($d{'MODEL.3D.DZ'}); $dz=$mdz; #+
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
		  $wrl="$wrlprefix/$wrl";
		}
		else
		{
		  $wrl=$kicadwrl{$component};
		  $lfak=1;
		}
	
	    $componentbodyavailable{$component}=1;
	
        if(defined($modelhints{$wrl}))
        {
		  #print "OK: $wrl\n";
          $pads{$component}.="#921 component:$component id:$id nr:$_[3]\n#".join("|",map { "$_=$_[0]{$_}" } sort keys %{$_[0]})." 0:".bin2hex($header)."\n    (model \"$wrl\"\n".$modelhints{$wrl}."\n";
        }		
		else
		{
		  #print "NOK: *$wrl*\n";
	      $pads{$component}.=<<EOF
#917
	(model "$wrl"
      (at (xyz $dx $dy $dz))
      (scale (xyz $lfak $lfak $lfak))
      (rotate (xyz $rot))
    )
EOF
;
        }
	  }
    }
	else
	{
	  print "NOT FOUND: $stp.wrl\n" if(defined($stp));
	}
  });
  
  sub pad3dRotate($$)
  {
    my $v=$_[0];
	my $angle=$_[1];
	if($v=~m/^(.*rotate \(xyz -?\d+ -?\d+\s+)(-?\d+)(\).*)$/s)
	{
	  my ($pre,$a,$post)=($1,$2,$3);
	  my $newa=($angle+$a); $newa-=360 if($newa>=360);
	  my $new=$pre.$newa.$post;
	  #print "\n************************\n$v\n******************\n ->\n************\n$new\n****************\n";
	  return $new;
	}
	else
	{
	  #print "error: $v\n";
	  #exit;
	}
	return $v;
  }


  our %shapes=();
  mkdir "wrlshp";
  
  print OUT "#Now handling Shape Based Bodies ...\n";
  HandleBinFile("$short/Root Entry/ShapeBasedComponentBodies6/Data.dat","\x0c",0,0, sub 
  { 
    my $value=$_[1];
    print OUT "#ShapeBasedComponentBodies#".$_[3].": ".bin2hex($value)."\n" if($annotate);
    #print "#ShapeBasedComponentBodies#".$_[3]."\n" if($annotate);
	my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean
	my $component=unpack("s",substr($value,7,2));
    print OUT "# ".bin2hex($unknownheader)."\n" if($annotate);
    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
	print OUT "#Text:$text\n" if($annotate);
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
	my $ncoords=unpack("l",substr($value,22+$textlen,4));
	print OUT "#ncoords: $ncoords\n" if($annotate);
	my $v7layer="F.CrtYd";
	$v7layer=$d{'V7LAYER'} eq "MECHANICAL1" ? "F.CrtYd":"B.CrtYd" if(defined($d{'V7LAYER'}));
	foreach(0 .. $ncoords-1)
	{
      my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($data,$_*37+1,4)));
	  my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($data,$_*37+5,4)));
      my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($data,$_*37+37+1,4)));
	  my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($data,$_*37+37+5,4)));
	  print OUT "#ShapeBasedAdhesiveLine\n" if($annotate);
	  print OUT "(gr_line (start $x1 $y1) (end $x2 $y2) (angle 90) (layer $v7layer) (width 0.2))\n";
	     #print "(gr_line (start $x1 $y1) (end $x2 $y2) (angle 90) (layer $v7layer) (width 0.2))\n";
	}
	
      #MODEL.MODELTYPE=0 => Box / Extruded PolyLine)
	  #MODEL.MODELTYPE=2 => Cylinder
	  #MODEL.MODELTYPE=3 => Sphere
	  #BODYOPACITY3D=1.000 => Opaque
	  #BODYOPACITY3D=0.500 => Half-transparent
	  #BODYOPACITY3D=0.000 => Invisible
	  #BODYCOLOR3D=255 => Red
	  #BODYCOLOR3D=65280 => Green
    my $col=$d{'BODYCOLOR3D'};
	my $red=($col&255)/255.0;
	my $green=(($col>>8)&255)/255.0;
	my $blue=(($col>>16)&255)/255.0;
	my $color=sprintf("%.5f %.5f %.5f",$red,$green,$blue);

	
	my $wrl="wrlshp/".substr($d{'MODELID'},0,14).".wrl"; $wrl=~s/[\{\}]//g;
	
    if($d{'MODEL.MODELTYPE'} == 0)
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=$d{'STANDOFFHEIGHT'};$pz=~s/mil//; $pz/=100; $pz=sprintf("%.7f",$pz);
	  my $sx=$d{'MODEL.2D.X'};$sx=~s/mil//; $sx/=100; $sx=sprintf("%.7f",$sx);
	  my $sy=$d{'MODEL.2D.Y'};$sy=~s/mil//; $sy/=100; $sy=sprintf("%.7f",$sy);
	  my $szmin=$d{'MODEL.EXTRUDED.MINZ'}; $szmin=~s/mil//; $szmin/=100; $szmin=sprintf("%.7f",$szmin);
	  my $sz=$d{'MODEL.EXTRUDED.MAXZ'}; $sz=~s/mil//; $sz/=100; $sz=sprintf("%.7f",$sz);
	  my @poly=();
	  my $prevx=undef; my $prevy=undef;
	  my $good=1;
	  foreach(0 .. $ncoords-1)
	  {
        my $x1=sprintf("%.8f",bmil2mm(substr($data,$_*37+1,4))-($componentatx{$component}||0));
	    my $y1=sprintf("%.8f",bmil2mm(substr($data,$_*37+5,4))+($componentaty{$component}||0));
		$good=0 if(defined($prevx) && near2d($prevx,$x1,$prevy,$y1));
        push @poly,"$x1 $y1" if(!defined($prevx) || $prevx ne $x1 || $prevy ne $y1);
		$prevx=$x1;
		$prevy=$y1;
      }
	  $shapes{$wrl}.=ExtrudedPolygon("0 0 $pz","0 0 0  0","$fak $fak 1",$color,"1",$sz,\@poly)."," if($good);
	}

	if($d{'MODEL.MODELTYPE'} == 1)
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=mil2mm($d{'STANDOFFHEIGHT'}); #$pz=~s/mil//; $pz/=100; 
	  my $sz=mil2mm($d{'OVERALLHEIGHT'})-$pz; #; $sz=~s/mil//; $sz/=100; $sz-=$pz;
      #$shapes{$wrl}.=Cone("0 0 0 ","0 0 0  0","1 1 1",$color,"1",$sz,"3").",";
	}

    if($d{'MODEL.MODELTYPE'} == 2)
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=$d{'STANDOFFHEIGHT'};$pz=~s/mil//; $pz/=100; 
	  
	  my $h=mil2mm($d{'MODEL.CYLINDER.HEIGHT'});  #$h=~s/mil//; $h/=100; $h=sprintf("%.7f",$h);
	  my $r=mil2mm($d{'MODEL.CYLINDER.RADIUS'});  #$r=~s/mil//; $r/=100; $r=sprintf("%.7f",$r);
      #$shapes{$wrl}.=Cylinder("0 0 0 ","0 0 0  0","1 1 1",$color,"1",$r,$h).",";
	}

    if($d{'MODEL.MODELTYPE'} == 3) #  Sphere
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=$d{'STANDOFFHEIGHT'};$pz=~s/mil//; $pz/=100; 
	  
	  #my $h=$d{'MODEL.CYLINDER.HEIGHT'};$h=~s/mil//; $h/=100; $h=sprintf("%.7f",$h);
	  #my $r=$d{'MODEL.CYLINDER.RADIUS'};$r=~s/mil//; $r/=100; $r=sprintf("%.7f",$r);
      #$shapes{$wrl}.=Sphere("0 0 0 ","0 0 0  0","1 1 1",$color,"1",$r,$pz).",";
	}

	

    
    $pads{$component}.=<<EOF
#1365
	(model "$wrlprefix/$wrl"
      (at (xyz 0 0 0))
      (scale (xyz 1 1 1))
      (rotate (xyz 0 0 0))
    )
EOF
;
	  
	#print "  ".bin2hex($data)."\n";
	#print "text: $text\n";
	#print "\n";
  });



  
  $componentid=0;
  HandleBinFile("$short/Root Entry/Components6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
    print OUT "#Components#".$_[3].": ".$_[1]."\n" if($annotate);
	print OUT "#\$pads{$componentid}\n" if($annotate);
	my $atx=mil2mm($d{'X'});$atx-=$xmove;
	my $aty=mil2mm($d{'Y'});$aty=$ymove-$aty;
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
	my $rot=sprintf("%.f",$d{'ROTATION'});
    my $stp=$d{'SOURCEDESIGNATOR'};
#	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'SOURCELIBREFERENCE'};
	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'PATTERN'};
	
	my $sourcelib=($d{'SOURCEFOOTPRINTLIBRARY'}||"");
	#SOURCELIBREFERENCE

	if(!defined($componentbodyavailable{$componentid}))
	{
	  if(defined($pads{$componentid}) && $pads{$componentid}=~m/\(model/)
	  {
	    #print "Where did the model come from? componentid: $componentid\n"; # !!! TODO
	  }
	
	  if(defined($kicadwrl{$componentid}) && !$pads{$componentid}=~m/\(model/)
	  {
	    print "No component body available for component $componentid, we could create our own for $reference now.\n";
	    print "wrl: $kicadwrl{$componentid}\n";
		my $wrl=$kicadwrl{$componentid};
		
        if(defined($modelhints{$wrl}))
        {
		  #print "OK: $wrl\n";
          $pads{$componentid}.="#985\n		  (model \"$wrl\"\n".$modelhints{$wrl}."\n";
        }		
		else
		{
		  print "NOK: *$wrl*\n";
	      $pads{$componentid}.=<<EOF
#991		  
	(model "$wrl"
      (at (xyz 0 0 0))
      (scale (xyz 1 1 1))
      (rotate (xyz 0 0 $rot))
    )
EOF
;
        }
	  }
	  else
	  {
	    #print "No mapping yet:\n";
        #print "    \"$reference\"=>\".wrl\",\n" if(!defined($kicadwrlerror{$reference}));
	    $kicadwrlerror{$reference}=1;

	  }
	}

	$rot=0 if(defined($pads{$componentid}) && $pads{$componentid}=~m/\.\/wrl\//);
	
    my $pad=pad3dRotate($pads{$componentid}||"",$rot);
    if(defined($pads{$componentid}) && $pads{$componentid}=~m/\.\/wrl\//)
	{
	  #print "Rewriting scale\n";
	  $pad=~s/\(scale\s*\(xyz 1 1 1\)\)/(scale (xyz $fak $fak $fak))/sg;
	  #print "Result: $pad\n";
	}
	
	
	#print "stp -> $rot\n";
    print OUT <<EOF
 (module $stp (layer $layer) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at $atx $aty)
    (path /539EEC0F)
    (attr smd)
	$pad
  )
EOF
if(defined($stp));
    $componentid++;
  });




  HandleBinFile("$short/Root Entry/Arcs6/Data.dat","\x01",0,0,sub 
  { 
    my $fn=$_[0]{'NAME'};
    my $value=$_[1];
	my $net=unpack("s",substr($value,3,2));
	my $component=unpack("s",substr($value,7,2));
	my $xorig=unpack("l",substr($value,13,4));
	my $yorig=unpack("l",substr($value,17,4));
  	my $x=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	my $y=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	my $r=bmil2mm(substr($value,21,4));
	my $layerorig=unpack("C",substr($value,0,1));
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "F.SilkS";
    my $sa=unpack("d",substr($value,25,8));
    my $ea=unpack("d",substr($value,33,8)); 

    my $angle=$ea-$sa; $angle=360+$ea-$sa if($ea<$sa);

	$sa=-$sa;
	$ea=-$ea;
    $angle=-$angle;
	
	#($sa,$ea)=($ea,$sa) if($sa>$ea);
    my $sarad=$sa/180*$pi;
	my $earad=$ea/180*$pi;
	my $width=bmil2mm(substr($value,41,4));
	
	
    my $x1=sprintf("%.5f",$x+cos($sarad)*$r);
	my $y1=sprintf("%.5f",$y+sin($sarad)*$r);
	my $x2=sprintf("%.5f",$x+cos($earad)*$r);
	my $y2=sprintf("%.5f",$y+sin($earad)*$r);

	print OUT "#Arc#$_[3]: ".bin2hex($value)."\n" if($annotate);
	print OUT "#Arc#$_[3]: xorig:$xorig yorig:$yorig layer:$layerorig component:$component\n" if($annotate);
	print OUT "#Arc#$_[3]: x:$x y:$y radius:$r layer:$layer sa:$sa ea:$ea sarad:$sarad earad:$earad width:$width x1:$x1 x2:$x2 y1:$y1 y2:$y2\n" if($annotate);
    print OUT "  (gr_arc (start $x $y) (end $x1 $y1) (angle $angle) (layer $layer) (width $width))\n" if($annotate);
	#print OUT "  (gr_text \"1\" (at $x1 $y1) (layer $layer))\n";
	#print OUT "  (gr_text \"2\" (at $x2 $y2) (layer $layer))\n";
	
	#print "ARC layer:$layer x:$x y:$y width:$width net:$net\n";
	#my $layer2=mapLayer(unpack("C",substr($value,1,1))) || "B.Cu";
	#print "".((-f "$short/Root Entry/Models/$fn")?"File exists.\n":"File $fn does NOT EXIST!\n");
	#$fn=~s/\.STEP$//i;$fn=~s/\.stp$//i;
	#print "R:".$_[0]{'ID'}."->$fn\n";
    #$modelname{$_[0]{'ID'}}=$fn;
  });

  # The following code reads Gerber Files that were converted to .kicad_pcb for automated reverse engineering below:
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
	print OUT "#Vias#".$_[3].": ".bin2hex($value)."\n" if($annotate);
    my $debug=($count<100);
    my $x=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	my $y=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	my $width=bmil2mm(substr($value,21,4));
	my $layer1="F.Cu"; # mapLayer(unpack("C",substr($value,0,1))); # || "F.Cu"; # Since Novena does not have any Blind or Buried Vias
	my $layer2="B.Cu"; # mapLayer(unpack("C",substr($value,1,1))); # || "B.Cu";
	my $net=unpack("s",substr($value,3,2))+2;
	
	#print "Layer: $layer1 -> $layer2\n";
	#print "Koordinaten:\n" if($debug);
	#print "x:$x y:$y width:$width\n" if($debug);
	print OUT "  (via (at $x $y) (size $width) (layers $layer1 $layer2) (net $net))\n" if($annotate);
	

	# The following was an experimental automatic reverse-engineering try. The code is disabled now.
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
	print OUT "#Polygons#".$_[3].": ".$_[1]."\n" if($annotate);
	my $counter=$_[3];
	my $width=mil2mm($d{'TRACKWIDTH'}||1);
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
	my $pourindex=$d{'POURINDEX'};
	if(defined($pourindex) && ( $pourindex<0 || $pourindex>100))
	{
	  print "Warning: Pourindex $pourindex out of the expected range (0 .. 100)\n";
	}
	my $net=($d{'NET'}||-1)+2; my $netname=$netnames{$net};
	#print "Polygon $_[3] has net $net\n";
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
	  my $thermalgap=$rules{'PolygonConnect.AIRGAP'} || "0.508";
	  my $thermalbridgewidth=$rules{'PolygonConnect.RELIEFCONDUCTORWIDTH'} || "0.508";
	  my $nettext=($net>1)?"(net $net) (net_name \"$netname\")":"";
	  my $priority=defined($pourindex)?"\n  (priority ".(100-$pourindex).")":"";
	  print OUT <<EOF
(zone $nettext (layer $layer) (tstamp 547BA6E6) (hatch edge 0.508) $priority
    (connect_pads thru_hole_only (clearance 0.09144))
    (min_thickness 0.254)
    (fill (mode segment) (arc_segments 32) (thermal_gap $thermalgap) (thermal_bridge_width $thermalbridgewidth))
    (polygon
      (pts     
EOF
;
	}
	
	foreach(0 .. $maxpoints-(($d{'POLYGONTYPE'} eq "Polygon" && $d{'HATCHSTYLE'} eq "Solid")?1:0))
	{
	  my $sx=mil2mm($d{'VX'.$_});$sx-=$xmove;
	  my $sy=mil2mm($d{'VY'.$_});$sy=$ymove-$sy;
	  my $ex=mil2mm($d{'VX'.($_+1)}||0);$ex-=$xmove;
	  my $ey=mil2mm($d{'VY'.($_+1)}||0);$ey=$ymove-$ey;
      #MarkPoint($sx,$sy) if($d{'POLYGONTYPE'} eq "Split Plane" && $counter eq 1);
	  print OUT "(gr_line (start $sx $sy) (end $ex $ey) (angle 90) (layer $layer) (width $width))\n" if($d{'POLYGONTYPE'} eq "Polygon" && $d{'POLYGONOUTLINE'} eq "TRUE");
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
	print OUT "#Tracks#".$_[3].": ".bin2hex($value)."\n" if($annotate);

    my $net=unpack("s",substr($value,3,2))+2;	  
    my $netname=$netnames{$net};
	my $component=unpack("s",substr($value,7,2));
    my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($value,21,4)));
	my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($value,25,4)));
	my $width=bmil2mm(substr($value,29,4));
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Cmts.User";
	
	if($layer =~m/(Edge\.Cuts|Silk|CrtYd|Adhes|Paste)/i)
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
    print OUT "#Fills#".$_[3].": ".bin2hex($value)."\n" if($annotate);

	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Cmts.User";
    my $net=unpack("s",substr($value,3,2))+2;	  
    my $netname=$netnames{$net};
    my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($value,21,4)));
	my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($value,25,4)));
    my $dir=sprintf('%.5f',unpack("d",substr($value,29,8))); 
	
    my $dir2=sprintf('%.5f',unpack("d",substr($value,38,8))||0); 

	
	#print "Koordinaten:\n";
	#print "x:$x1 y:$y1 dir:$dir dir2:$dir2\n";
    my $nettext=($net>1)?"(net $net) (net_name \"$netname\")":"";
	print OUT <<EOF
	  (zone $nettext (layer $layer) (tstamp 53EB93DD) (hatch edge 0.508)
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
    print OUT "#Regions#".$_[3].": ".bin2hex(substr($value,0,1000))."\n" if($annotate);
	my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean
    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
	print OUT "#$text\n" if($annotate);
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
  
  

  open VOUT,">wrlshapes.kicad_pcb";
  print VOUT <<EOF
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
    (trace_clearance 0.127)
    (zone_clearance 0.0144)
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

  my $nshape=0;
  foreach(sort keys %shapes)
  {
    open WRLOUT,">$_";
	print WRLOUT "#VRML V2.0 utf8\n";
    print WRLOUT "Group { children [\n";
	print WRLOUT $shapes{$_};
	print WRLOUT "] }\n";
	close WRLOUT;
	my $atx=($nshape%10)*30+30;
	my $aty=int($nshape/10)*30+30;
	#wrlshapes.kicad_pcb
	print VOUT <<EOF
  (module A$nshape (layer F.Cu) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at $atx $aty)
    (path /539EEC0F)
    (attr smd)
	(model "$wrlprefix/$_"
      (at (xyz 0 0 0))
      (scale (xyz 1 1 1))
      (rotate (xyz 0 0 0))
    )
    (pad "1" smd oval (at 0.0 0.0) (size 0.60000 2.20000) 
      (layers F.Cu F.Mask F.Paste)
    )
  )
EOF
;
	$nshape++;
  }
  print VOUT ")\n";
  close VOUT;
  print OUT "#Finished handling Shape Based Bodies.\n";

  
  sub ucs2utf($)
  {
    my $r=$_[0]; $r=~s/\x00//gs;
	return $r;
  }
  
  if(1)
  {
    print "Texts6...\n";
	# It seems there are files with \r\n and files with \n but we don´t know how to distinguish those. Perhaps it depends on the Alitum version?
    my $content=readfile("$short/Root Entry/Texts6/Data.dat"); $content=~s/\r\n/\n/sg unless($filename=~m/EDA/);
	my $pos=0;
	my %seen=();
	while($pos<length($content))
	{
	  my $opos=$pos;
	  last if(substr($content,$pos,1) ne "\x05"); 
	  #print "pos: $pos\n";
	  $pos++;
      my $fontlen=unpack("l",substr($content,$pos,4)); 
	  $pos+=4;
	  my $component=unpack("s",substr($content,$pos+7,2));
	  my $texttype=unpack("C",substr($content,$pos+21,1));
	  my $hide=0;
	  if($component>=0)
	  {
	    if($texttype == 0xc0)
		{
		  $hide=1 if($commenton{$component} eq "FALSE");
		}
		if($texttype == 0xf2)
		{
		  $hide=1 if($nameon{$component} eq "FALSE");
		}
	  }
	  
	  my $layer=mapLayer(unpack("C",substr($content,$pos,1))) || "Cmts.User";
	  my $olayer=unpack("C",substr($content,$pos,1));
	  my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($content,$pos+13,4)));
	  my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($content,$pos+17,4)));
      my $width=bmil2mm(substr($content,$pos+21,4));
	  my $dir=unpack("d",substr($content,$pos+27,8)); 
	  my $mirror=unpack("C",substr($content,$opos+39,1));
	  my $font=substr($content,$pos,$fontlen); 
	  $pos+=$fontlen;
	  my $fontname=ucs2utf(substr($font,46,64));
      my $textlen=unpack("l",substr($content,$pos,4)); 
	  $pos+=4;
	  my $text=substr($content,$pos+1,$textlen-1); 
	  $pos+=$textlen;
	  print OUT "#Texts#".$opos.": ".bin2hex(substr($content,$opos,$pos-$opos))."\n" if($annotate);
	  print OUT "#Layer: $olayer Component:$component Type:".sprintf("%02X",$texttype)."\n" if($annotate);
	  print OUT "#Commenton: ".$commenton{$component}." nameon: ".$nameon{$component}."\n" if($component>=0 && $annotate);
	  print OUT "#Mirror: $mirror\n";
	  my $mirrortext=$mirror?" (justify mirror)":"";
	  print OUT "#hide: $hide ($text)\n" if($annotate);
	  $text=~s/"/''/g;
	  print OUT <<EOF
 (gr_text "$text" (at $x1 $y1 $dir) (layer $layer)
    (effects (font (size $width $width) (thickness 0.1)) (justify left)$mirrortext)
  )
EOF
        if(!$hide);
	}
  } 

  # We are done with converting a .PcbDoc file, now we print some statistical information: 
  if(keys %unmappedLayers)
  {
    print "Unmapped Layers:\n";
    print join ",",map { "\"$_\"=>\"$unmappedLayers{$_}\""} keys %unmappedLayers;
    print "\n";
  }
  
  foreach(sort keys %usedlayers)
  {
    my $name="undefined"; $name=$1 if($layerdoku=~m/name: *$_ *([\w.]+)/);
	my $kic=$layermap{$_} || "undefined";
	my $lname=$layername{$_} || "undefined";
    #print "Used layer: $_ $lname/$name -> $kic\n";
  }
  
  print OUT ")\n";
}
if(!$filecounter)
{
  print "There were no unpacked PcbDoc files found. Please unpack them with unpack.pl before running convertpcb.pl\n";
}


sub rem0($)
{
  my $d=$_[0]; $d=~s/\x00//g;
  return $d;
}

# The following function decodes an old Alitum version 9? .lib file
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


# This function opens the given filename and decodes a .SchLib file
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
 # decodeSchLib($_);
}

# This function decodes a new Altium .PcbLib file
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
	  
	  #type: 0 => Contains V7-|seperated|values| , afterwards a list of coordinates follow
	  #type: 2 => Pad
	  #type: 4 => Track
	  #type: 12 => ShapeBasedComponentBodies6 - First byte seems to contain the layer, the rest has been always the same until now
      #type: 6 => Fills
	  
	  #MODEL.MODELTYPE=0 => Box / Extruded PolyLine)
	  #MODEL.MODELTYPE=2 => Cylinder
	  #MODEL.MODELTYPE=3 => Sphere
	  #BODYOPACITY3D=1.000 => Opaque
	  #BODYOPACITY3D=0.500 => Half-transparent
	  #BODYOPACITY3D=0.000 => Invisible
	  #BODYCOLOR3D=255 => Red
	  #BODYCOLOR3D=65280 => Green
	  
      $pos+=$typelen+5;
	  print "Error in decoding!\n" if($pos>length($content));
	  $prevtype=$type;
	}
  }
}

foreach(glob("'library/Miscellaneous Devices/Root Entry/PcbLib/0/Root Entry/*/Data.dat.bin'"))
{
 #decodePcbLib($_);
}
foreach(glob("'TestsSrc/Root Entry/*/Data.dat.bin'"))
{
  #decodePcbLib($_);
}

foreach(glob("ASCII*.PcbDoc"))
{
  next;
  next unless($annotate);
  my $line="";
  print "Documenting $_\n";
  open IN,"<$_";
  my %h=();
  while($line=<IN>)
  {
    my @a=split '\|',$line;
    my %d=();
	my $recordtype="";
	foreach my $c(@a)
	{
  	  #print "$c\n";
      if($c=~m/^([^=]*)=(.*)$/)
	  {
  	    my $name=$1;
	    my $value=$2;
		$d{$name}=$value;
      }
 	}
	foreach my $c(@a)
	{
  	  #print "$c\n";
      if($c=~m/^([^=]*)=(.*)$/)
	  {
  	    my $name=$1;
	    my $value=$2;
		$h{$d{"RECORD"}.($d{'MODEL.MODELTYPE'}||"")}{$name}{$value}=1;
      }
 	}


    
  }
  close IN;
  open OUT,">$_.txt";
  foreach my $record (sort keys %h)
  {
    print OUT "\nModel for RECORD=$record:\n";
    foreach(sort keys %{$h{$record}})
	{
	  if(scalar(keys %{$h{$record}{$_}})>0)
	  {
	    print OUT "$_={".join(",",sort keys %{$h{$record}{$_}})."}\n";
	  }
	}
	print OUT "\n";
  }
  close OUT;
}


