#!/usr/bin/perl -w
use strict;
use Compress::Zlib;
use FindBin;
use lib "$FindBin::Bin";
use Math::Geometry::Planar;
use Data::Dumper;
use Cwd qw(abs_path cwd getcwd);
use File::Glob qw(:globally :nocase);
#use Math::Bezier;

# Things that are missing in KiCad:
# Octagonal pads, needed for Arduino designs (converting them to circles can cause overlaps!)
# More than 32 layers, seems not to be a big problem at the moment
# Multi-line Text Frames (Workaround: The text can be rendered by the converter)
# A GND symbol with multiple horizontal lines arranged as a triangle
# Individual colors for single objects like lines, ...
# Ellipse (Workaround: we could approximate them with Polylines)
# Elliptical Arc (Workaround: we could approximate them with Polylines)
# Element Classes (All Top Components, All Bottom Components, HDMI, Power, All Resistors...)
# Board regions for Rigid-Flex
# Support for STEP files
# Rounded Rectangles (Not just ovals that are circles when they are even sided
# Novena had too many netclasses for KiCad <BZR 5406, the NetClass editor in the Design Rules Editor vanished due to GUI layout when there are too many netclasses: https://bugs.launchpad.net/kicad/+bug/1418135
# Loading the 3D viewer is slow, especially when the zones are filled. It only utilizes a single core.
# The 3D view currently has a problem with relative pathes: https://bugs.launchpad.net/kicad/+bug/1417786  a workaround is available with the $absoluteWRLpath option
# Additional paramters in PCBnew for components that could be used for the BOM
# Odd-numbered amount of layers in PCB design (e.g. 5 layers)

# Things that are missing in Designer:
# The Zone-Fill-Polygons are not saved in the file. Workaround: Press "b" in PcbNew or: select the zone tool, right-click on an empty area, then "Fill all zones"
# Annotations in the fileformat

# Todos for this converter:
# Wrong recordtype errors for Regions6
# Correct positioning for Cones, Cylinders, ... 


my $annotate=0;

my $absoluteWRLpath=0;

my $wrlprefix=$absoluteWRLpath ? Cwd::cwd() : ".";


our %shownwarnings=();

{
  my $ofh = select STDOUT;
  $|=1;
  select $ofh;
}


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
FileVersionInfo # Messages for when the file is opened in older Designer versions that do not support certain features in this fileformat
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
Texts # Warnings for older Designer versions, I think we don´t need to support those ;-)
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

# Truth values
our %alttruth=("0"=>"False","1"=>"True");
our %altrule=("1"=>"Rule","2"=>"Manual");


our %fieldlabels=();
our %bytelabels=();
our %linebreaks=();
sub msubstr # My SubString is a substr function that annotates the fields while substringing them
{
  $fieldlabels{$_[0]}{$_[1]}{$_[2]}=$_[3]||"?";
  $bytelabels{$_}=$_[3]||"?" foreach($_[1] .. $_[1]+$_[2]-1);
  if($_[1]>length($_[0]))
  {
    my ($package,$filename,$line,$subroutine) = caller(0);
    print STDERR "Error: substring out of range: length:".length($_[0])." pos:$_[1] wantedsize:$_[2] field:$_[3] ($package,$filename:$line - $subroutine)\n";
    return undef;
  }
  return substr($_[0],$_[1],$_[2]);
}
sub dumpAnnotatedHex($)
{
  my $value=$_[0];
  my $content="";
  #print "Starting loop:\n";
  my $prev="";
  foreach(0 .. length($value)-1)
  {
    $content.="<br/>".("&#160;" x $linebreaks{$_})  if($linebreaks{$_});
    my $this=$bytelabels{$_}||"";
	my $next=$bytelabels{$_+1}||"";
    $content.="<div title='$this $_' style='background-color:".($this?"yellow":"white").";'>" if($prev ne $this);
	$content.=sprintf("%02X",unpack("C",substr($value,$_,1)));
	$content.= $this eq $next ? " ":"</div> ";
	$prev=$this;
  }
  #print "Done.\n";
  $content.="\n<br/><br/>\n";
  return $content;
}

# Convert mil to millimeters
sub mil2mm($)
{
  return undef unless(defined($_[0]));
  my $data=$_[0];
  $data=~s/mil$//;
  $data/=$faktor;
  return (sprintf("%.5f",$data) + 0);
}
# Convert binary mil to millimeter
sub bmil2mm($)
{
  return (sprintf("%.5f",unpack("l",$_[0])/$faktor/10000) + 0);
}
# Convert binary mil to ascii mil
sub bmil2($)
{
  return (unpack("l",$_[0])/10000)."mil";
}

# Necessary for comments
sub escapeCRLF($)
{
  my $d=$_[0];
  $d=~s/\n/\\n/gs;
  return $d;
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
  return "" if(!defined($orig) || $orig eq "");
  foreach(0 .. length($orig)-1)
  {
    $value.=sprintf("%02X",unpack("C",substr($orig,$_,1)));
  }
  return $value;
}

# This function converts a binary string to its hex representation for debugging
sub bin2hexLF($)
{
  my $orig=$_[0];
  my $value="";
  return "" if(!defined($orig) || $orig eq "");
  foreach(0 .. length($orig)-1)
  {
    $value.="\n##" if(($_ % 100)==99);
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

# Are 2 points near each other? near2d(x1,x2,y1,y2)
sub near2d($$$$)
{
  my $d=0.0001;
  return (sqrt(($_[0]-$_[1])*($_[0]-$_[1])+($_[2]-$_[3])*($_[2]-$_[3]))<$d);
}

# Reformat scientific notation for angles for ascii format
sub enull($)
{
  my $d=$_[0];
  $d=~s/E\+/E+0/; $d=~s/E\-/E-0/;  $d=~s/^/ /;
  return $d;
}


# Guess the binary encoding of a given field value
# Alternatively, we might want to output a list of all possible encodings for a given field value
sub EstimateEncoding($)
{
  my $v=$_[0];
  if($v=~m/-?\d+\.?\d*mil$/)
  {
    $v=~s/mil$//;
    return pack("l",$v*10000);
  }
  if($v=~m/^ ?(\d+\.\d+E\+\d+)$/)
  {
    return pack("d",$1);
  }
  return "\x01" if($v eq "TRUE");
  return "\x00" if($v eq "FALSE");
  
  return "\x01" if($v eq "Rule");
  return "\x02" if($v eq "Manual");
  
  return pack("C",$v) if($v =~m/^\d{1,3}$/ && $v<256);
  return pack("s",$v) if($v =~m/^-?\d{1,4}$/ && $v>=-65536 && $v <65536);
  return $v;
}

our $version="";

sub getCRLF($)
{
  my $d=$_[0];
  return $d if($d=~m/[^\r]\n/);	
  return $d if(defined($ARGV[0]) && $ARGV[0] eq "CRLF");
  $d=~s/\r\n/\n/sg unless($version eq "5.01");
  return $d;
}

my %widths=();


open HOUT,">Pads.html";
print HOUT <<EOF
	<html>
<head>
<style>
div {display: inline;}
</style>
</head>
<body>
<pre>
EOF
;
open DOUT,">Pads.txt";

our $cutcounter=0;

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



# This is the main handling function that parses most of the binary files inside a .PcbDoc
# It iterates over all records in the given file, and callback´s a given function for every record given
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
  $content=getCRLF($content);
  return unless length($content)>4;
  
  my $text="";
  my @a=();
  my %h=();
  
  print "Writing to $filename.txt\n";
  open HBOUT,">$filename.txt";
  my $line=0;
  my $pos=0;
  
  while($pos<length($content)-4 && $pos>=0)
  {
    my $header=substr($content,$pos,$headerlen);
    $pos+=$headerlen;
    my $rtyp=substr($content,$pos,length($recordtype));
	if($rtyp ne $recordtype && !($recordtype eq "\x01\x00" && $rtyp=~m/^(\x01|\x03|\x05|\x07|\x08)\x00$/)) # Dimensions have both 01:00 and 05:00 record types
	{
	  print "ERROR: Wrong recordtype: ".bin2hex($rtyp).", expected ".bin2hex($recordtype)." at pos $pos.\n";
	  if(!$ARGV[0] eq "CRLF")
	  {
	    print "The wrong record type could be a new record type, or a decoding error due to wrong CRLF encoding.\n";
		print "We are trying again now with a different CRLF encoding.\n";
	    system "$0 CRLF";
		exit;
	  }
	  else
	  {
	    print "This record type is really unknown. Please contact the developer to add it.\n";
	  }
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

# Generates the 3D WRL content for a Box
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


sub Sphere($$$$$$$)
{
  # Needs to be implemented
  return "";
}

# Generates the 3D WRL content for an extruded Polygon
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
  if(scalar(@polyarray)<3)
  {
    return undef;
  }
  #print "Count: ".scalar(@polyarray)."\n";
  
  my $poly = Math::Geometry::Planar->new;
  $poly->points(\@polyarray);
  $poly->cleanup();
  #print "Convex: ".$poly->isconvex()."\n";
  #print "IsSimple: ".$poly->issimple()."\n";
  if(!$poly->isconvex()) # We should also allow concave, non-self-crossing polygons
  #if(!$poly->issimple()) # This unfortunately does not work
  {
    return undef;
  }
  my @triangles=$poly->triangulate();
  #print "Done\n";
  
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
  center 0 0 0
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


# Generates the 3D WRL content for a Cylinder
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
  
  my $h2=$h/2;
 
  return <<EOF
Transform
{
  translation $translation
  rotation $rotation
  scale $scale
  scaleOrientation 0 0 1  0
  center 0 0 $h2
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

# Generates the 3D WRL content for a Cone
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
    (9 In9.Cu signal)
    (10 In10.Cu signal)
    (11 In11.Cu signal)
    (12 In12.Cu signal)
    (13 In13.Cu signal)
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
  
our %altlayername=("1"=>"TOP","2"=>"MID1","3"=>"MID2","4"=>"MID3","5"=>"MID4","6"=>"MID5","7"=>"MID6","8"=>"MID7","9"=>"MID8","10"=>"MID9","11"=>"L7","12"=>"L8","32"=>"BOTTOM","33"=>"TOPOVERLAY",
  "34"=>"BOTTOMOVERLAY","35"=>"TOPPASTE","36"=>"BOTTOMPASTE",
  "37"=>"TOPSOLDER","38"=>"BOTTOMSOLDER","39"=>"PLANE1","40"=>"PLANE2","41"=>"PLANE3","42"=>"PLANE4","43"=>"PLANE5","44"=>"PLANE6",
  "55"=>"DRILLGUIDE","56"=>"KEEPOUT","57"=>"MECHANICAL1","58"=>"MECHANICAL2",
  "59"=>"MECHANICAL3","60"=>"MECHANICAL4","61"=>"MECHANICAL5","62"=>"MECHANICAL6","63"=>"MECHANICAL7","64"=>"MECHANICAL8","65"=>"MECHANICAL9",
  "66"=>"MECHANICAL10","67"=>"MECHANICAL11","68"=>"MECHANICAL12",
  "69"=>"MECHANICAL13","70"=>"MECHANICAL14","71"=>"MECHANICAL15","72"=>"MECHANICAL16","73"=>"DRILLDRAWING","74"=>"MULTILAYER");


# At first we read the curated Designer->KiCad standard component mappings:
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


our %result=();
our %cgoodbad=();
our %rawbinary=();

my $trackwidth=10;

# The following are the movement coordinates to align the Novena PCB to Gerber-Imports
my $xmove=95.3; 
my $ymove=79.6; 
# The following are the movement coordinates to put the board into the normal workspace
#$xmove=50;$ymove=250; # Enable to move Novena mainboard into the frame, or disable to move it to align to the Gerber-Imports

$xmove=0; $ymove=0; # Enable to align GPBB to the Gerber Imports


our %componentatx=();
our %pads=();
our %componentaty=();
our %netnames=("1"=>"Net1");

our $count=0;

sub HandleFill($$$$)
{ 
    my $value=$_[1];
    print OUT "#Fills#".escapeCRLF($_[3]).": ".bin2hexLF($value)."\n" if($annotate);
    $rawbinary{"Fill"}{$_[3]}=$_[1];
	my $component=unpack("s",substr($value,7,2));
	assertdata("Fill",$_[3],"COMPONENT",unpack("s",substr($value,7,2))) if($component>=0);
	# What can we do with Fills that are parts of Components?	
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "Cmts.User";
    assertdata("Fill",$_[3],"LAYER",$altlayername{unpack("C",substr($value,0,1))});
    my $net=unpack("s",substr($value,3,2))+2;	  
    assertdata("Fill",$_[3],"NET",unpack("s",substr($value,3,2))) if($net>1);
    my $netname=$netnames{$net};
    my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
    assertdata("Fill",$_[3],"X1",bmil2(substr($value,13,4)));
	my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
    assertdata("Fill",$_[3],"Y1",bmil2(substr($value,17,4)));
	my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($value,21,4)));
    assertdata("Fill",$_[3],"X2",bmil2(substr($value,21,4)));
	my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($value,25,4)));
    assertdata("Fill",$_[3],"Y2",bmil2(substr($value,25,4)));
    my $dir=sprintf('%.5f',unpack("d",substr($value,29,8))); 
    assertdata("Fill",$_[3],"ROTATION",enull(sprintf("%.14E",unpack("d",substr($value,29,8)))));
	
    my $dir2=sprintf('%.5f',unpack("d",substr($value,38,8))||0); 

    my $USERROUTED=length($value)>45?unpack("C",substr($value,45,1)):0; # AUTOGENERATED
    assertdata("Fill",$_[3],"USERROUTED",uc($alttruth{$USERROUTED}));
	
	 
	
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
}

sub HandleTrack($$$$)
{ 
    my $value=$_[1];
	print OUT "#Tracks#".escapeCRLF($_[3]).": ".bin2hexLF($value)."\n" if($annotate);
    $rawbinary{"Track"}{$_[3]}=$_[1];
    my $net=unpack("s",substr($value,3,2))+2;	 
	assertdata("Track",$_[3],"RECORD","Track");
	assertdata("Track",$_[3],"INDEXFORSAVE",$_[3]);
	assertdata("Track",$_[3],"NET",unpack("s",substr($value,3,2))) if($net>=2);
    my $netname=$netnames{$net};
	my $component=unpack("s",substr($value,7,2));
	assertdata("Track",$_[3],"COMPONENT",unpack("s",substr($value,7,2))) if($component>=0);
    my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	assertdata("Track",$_[3],"X1",bmil2(substr($value,13,4)));
	my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	assertdata("Track",$_[3],"Y1",bmil2(substr($value,17,4)));
	my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($value,21,4)));
	assertdata("Track",$_[3],"X2",bmil2(substr($value,21,4)));
	my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($value,25,4)));
	assertdata("Track",$_[3],"Y2",bmil2(substr($value,25,4)));
	my $width=bmil2mm(substr($value,29,4));
	assertdata("Track",$_[3],"WIDTH",bmil2(substr($value,29,4)));
    my $olayer=unpack("C",substr($value,0,1));
	my $layer=mapLayer($olayer) || "Cmts.User";
	assertdata("Track",$_[3],"LAYER",$altlayername{$olayer}) if(defined($altlayername{$olayer}));
	print STDERR "altlayername{$olayer} undefined\n" if(!defined($altlayername{$olayer}));

    my $keepout=unpack("C",substr($value,2,1)); # AUTOGENERATED
	assertdata("Track",$_[3],"KEEPOUT",$keepout==2?"TRUE":"");
	
    my $polygon=unpack("s",substr($value,5,2)); # AUTOGENERATED
	assertdata("Track",$_[3],"POLYGON",$polygon) if($polygon>=0);
	
    my $UNIONINDEX=unpack("C",substr($value,36,1)); # AUTOGENERATED
	assertdata("Track",$_[3],"UNIONINDEX",$UNIONINDEX);
	
	my $USERROUTED=length($value)>44?unpack("C",substr($value,44,1)):0; # AUTOGENERATED
	assertdata("Track",$_[3],"USERROUTED",uc($alttruth{$USERROUTED}||""));
	
	# On Edge, Silkscreen, ... layers, we have to use lines, on copper layers we have to use segments
    if($_[3]=~m/PCBLIB-/)
	{
	  print OUT "  (fp_line (start $x1 $y1) (end $x2 $y2) (layer $layer) (width $width))\n"; #(angle 45) 
	}
	elsif($layer =~m/(Edge\.Cuts|Silk|CrtYd|Adhes|Paste)/i)
	{
	  $cutcounter++;
	  #$width="0.$cutcounter";
	  #print "  (gr_line (start $x1 $y1) (end $x2 $y2) (layer $layer) (width $width))\n";
	  print OUT "  (gr_line (start $x1 $y1) (end $x2 $y2) (layer $layer) (width $width))\n"; #(angle 45) 
	}
	else
	{
	  print OUT "  (segment (start $x1 $y1) (end $x2 $y2) (width $width) (layer $layer) (net $net))\n";
	}
	
	# Automated verification against the Gerbers
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
	      #print "DEBUG: ".bin2hex($value)."\n\n";
		}
	  }
	}
	$count++;
}

sub HandleArc($$$$) # $filename,$value,?,$data   (\%d,$data,$header,$line);
{ 
    my $fn=$_[0]{'NAME'};
    my $value=$_[1];
	my $net=unpack("s",substr($value,3,2));
    $rawbinary{"Arc"}{$_[3]}=$_[1];
	assertdata("Arc",$_[3],"RECORD","Arc");
	assertdata("Arc",$_[3],"INDEXFORSAVE",$_[3]);
	assertdata("Arc",$_[3],"NET",$net) if($net>0);
	my $component=unpack("s",substr($value,7,2));
	assertdata("Arc",$_[3],"COMPONENT",$component) if($component>=0);
	my $xorig=unpack("l",substr($value,13,4));
	assertdata("Arc",$_[3],"LOCATION.X",bmil2(substr($value,13,4)));
	my $yorig=unpack("l",substr($value,17,4));
	assertdata("Arc",$_[3],"LOCATION.Y",bmil2(substr($value,17,4)));
  	my $x=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	my $y=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	my $r=bmil2mm(substr($value,21,4));
	assertdata("Arc",$_[3],"RADIUS",bmil2(substr($value,21,4)));
	my $layerorig=unpack("C",substr($value,0,1));
	assertdata("Arc",$_[3],"LAYER",$altlayername{$layerorig}||$layerorig);
	my $layer=mapLayer(unpack("C",substr($value,0,1))) || "F.SilkS";
    my $sa=unpack("d",substr($value,25,8));
	assertdata("Arc",$_[3],"STARTANGLE",enull(sprintf("%.14E",$sa)));
    my $ea=unpack("d",substr($value,33,8)); 
	assertdata("Arc",$_[3],"ENDANGLE",enull(sprintf("%.14E",$ea)));
    my $USERROUTED=length($value)>55?unpack("C",substr($value,55,1)):0; # AUTOGENERATED
	assertdata("Arc",$_[3],"USERROUTED",uc($alttruth{$USERROUTED}||""));
	my $UNIONINDEX=unpack("C",substr($value,48,1)); # AUTOGENERATED, this field could be larger, maximum 4 bytes I guess
	assertdata("Arc",$_[3],"UNIONINDEX",$UNIONINDEX);
	
    my $angle=$ea-$sa; $angle=360+$ea-$sa if($ea<$sa);

	$sa=-$sa;
	$ea=-$ea;
        $angle=-$angle;

        if($ea>$sa)
	{
	  $ea-=360;
        }

	#($sa,$ea)=($ea,$sa) if($sa>$ea);
        my $sarad=$sa/180*$pi;
	my $earad=$ea/180*$pi;
	my $width=bmil2mm(substr($value,41,4));
	assertdata("Arc",$_[3],"WIDTH",bmil2(substr($value,41,4)));

        my $x1=sprintf("%.5f",$x+cos($sarad)*$r);
	my $y1=sprintf("%.5f",$y+sin($sarad)*$r);
	my $x2=sprintf("%.5f",$x+cos($earad)*$r);
	my $y2=sprintf("%.5f",$y+sin($earad)*$r);
	my $xm=sprintf("%.5f",$x+cos(($sarad+$earad)/2)*$r);
	my $ym=sprintf("%.5f",$y+sin(($sarad+$earad)/2)*$r);

	print OUT "#Arc#$_[3]: ".bin2hexLF($value)."\n" if($annotate);
	print OUT "#Arc#$_[3]: xorig:$xorig yorig:$yorig layer:$layerorig component:$component\n" if($annotate);
	print OUT "#Arc#$_[3]: x:$x y:$y radius:$r layer:$layer sa:$sa ea:$ea sarad:$sarad earad:$earad width:$width x1:$x1 x2:$x2 y1:$y1 y2:$y2\n" if($annotate);
	if(($r*1.0)<=($width/2.0))
	{
		print OUT "#Arc#$_[3]: WARNING: width/2 exceeds radius*1.01 !\n" if($annotate);
		$width=$r/2.0;
	}
    print OUT "  (arc (start $x1 $y1) (end $x2 $y2) (mid $xm $ym) (layer $layer) (width $width) ".($net>=0?"(net $net)":"").")\n";

	#print OUT "  (gr_text \"1\" (at $x1 $y1) (layer $layer))\n";
	#print OUT "  (gr_text \"2\" (at $x2 $y2) (layer $layer))\n";
	
	#print "ARC layer:$layer x:$x y:$y width:$width net:$net\n";
	#my $layer2=mapLayer(unpack("C",substr($value,1,1))) || "B.Cu";
	#print "".((-f "$short/Root Entry/Models/$fn")?"File exists.\n":"File $fn does NOT EXIST!\n");
	#$fn=~s/\.STEP$//i;$fn=~s/\.stp$//i;
	#print "R:".$_[0]{'ID'}."->$fn\n";
    #$modelname{$_[0]{'ID'}}=$fn;
}



sub HandlePads($$)
{
    my $value=$_[0];
	my $filename=$_[1];
	my $pos=0;
	my $counter="0";

	%linebreaks=();
	%bytelabels=();
	while(($pos+10)<length($value) && $pos>=0)
	{
	  #print "Loop: pos: $pos(".sprintf("0x%X",$pos).")\n";
	  my $opos=$pos;
#	  #$linebreaks{$pos}=1;
#	  if(msubstr($value,$pos,1,"Type") =~m/[\x80\x86]/)
#	  {
#	    $pos+=1302/2;
#		print STDERR "ERROR: 0x80 / 0x86 found in pads\n";
#		next;
#	  }
#	  if(msubstr($value,$pos,1,"Type") =~m/[\x00]/)
#	  {
#	    $pos+=1402/2;
#		print STDERR "ERROR: 0x00 found in pads\n";
#	    #print "Checking2... pos:$pos\n";
#	    if(msubstr($value,$pos,1,"Type") ne "\x02" && (length($value)>$pos+0x1e0) && substr($value,$pos+0x1e0,1) eq "\x02")
#  	    ##{
#	       print "Seems we should skip 0x1e0 bytes\n";
#		   $pos+=0x1e0;
# #       }		
#		next;
#	  }
      my $recordtype=msubstr($value,$pos,1,"RecordType");
      if($recordtype ne "\x02")
	  {
	    my %str=("NAME"=>$filename);
		#HandleBinFile("$short/Root Entry/Arcs6/Data.dat","\x01",0,0,sub 
		while($pos<length($value)-10)
		{
		  $linebreaks{$pos}=1;
		  my $slen=unpack("V",msubstr($value,$pos+1,4,"Len"));
		  #print "slen: $slen\n";
		  my $snippet=substr($value,$pos+5,$slen);
		  print "Snippet: ".bin2hex($snippet)."\n";
		  if($recordtype eq "\x01")
		  {
		    print "Arc\n";
	        HandleArc(\%str,$snippet,0,$pos);
	      }
		  elsif($recordtype eq "\x04")
		  {
		    print "Track\n";
	        HandleTrack(\%str,$snippet,0,"PCBLIB-".$pos);
		  }
		  elsif($recordtype eq "\x06")
		  {
		    print "Fill\n";
	        HandleFill(\%str,$snippet,0,$pos);
		  }
		  else
		  {
		    print "Unhandled Record Type: ".unpack("C",$recordtype)."\n";
		  }
		  $pos+=$slen+4+1;
		  $linebreaks{$pos}=1;
		  last;
		}
		next;
      }
	  elsif($recordtype ne "\x02")
	  {
	  
	  
	  
            my $xpos=sprintf("0x%X",$pos);
			print "ERROR: Parsing error in Pads, header code 02 does not match ".bin2hex(substr($value,$pos,1))." at pos $pos# ($xpos)\n";
			last;
			# The following code is for back-tracking and searching for another pad start in the file:
			my $spos=$pos-30;
			my $found=0;
			foreach($spos .. length($value)-100)
			{
			  if(substr($value,$_,1) eq "\x02")
			  {
			    print "Found a potential startbyte at $_\n";
				print "V: ".unpack("V",substr($value,$_+1,4))."\n";
				print "C: ".unpack("C",substr($value,$_+5,1))."\n";
			    if(unpack("V",substr($value,$_+1,4)) == unpack("C",substr($value,$_+5,1))+1)
				{
				   $pos=$_;
				   $found=1;
				   print "Found next start at $_\n";
				   last;
				}
			  }
			}
			if(!$found)
			{
			  print "ERROR: Cannot find another start byte 0x02\n";
              last;
			}
	  }
	  
	  my @starts=();
	  my @lengths=();
	  my @contents=();
	  
	  my $len=unpack("V",msubstr($value,$pos+1,4,"len"));
	  my $namelen=unpack("C",msubstr($value,$pos+5,1,"namelen"));


	  my $tpos=$pos+1;
	  foreach(0 .. 5)
	  {
		$linebreaks{$tpos}=3;
	    $starts[$_]=$tpos+4;
		$lengths[$_]=unpack("V",msubstr($value,$tpos,4,"len[$_]"));
		$contents[$_]=substr($value,$tpos,$lengths[$_]);
		$tpos+=4+$lengths[$_];
	  }
	  $linebreaks{$tpos}=1;
	  #print "len: $len\n";
	  
	  if($len>256 || $len<0)
	  {
	    print "ERROR: Parsing error with length: $len at position $pos+1 (".sprintf("0x%X",$pos+1).")\n";
		last;
	  }
  	  $linebreaks{$pos}=1;

	  my $name=msubstr($value,$pos+6,$len-1,"name");
      #print "Name: $name\n";
	  
	  assertdata("Pad",$counter,"RECORD","Pad");
  	  assertdata("Pad",$counter,"INDEXFORSAVE",$counter);
	  assertdata("Pad",$counter,"NAME",$name);
	  
	  #$pos+=5+$len; # This ignores the length of the initial fields, and is therefore wrong
	  
	  $pos=$starts[4]-23; # This correctly parses the initial fields. Unfortunately the rest of the code depends on the pos being 23 bytes ahead of the start of this field, so we set the pos accordingly here.
	  #print "Difference: ".($starts[4]-$pos)."\n";
	  
	  
	  #$linebreaks{$pos}=1;
	  #print "pos: ".sprintf("0x%X",$pos+143)."\n";
  	  #my $len2=unpack("V",msubstr($value,$pos+143,4,"len2")); # This len2 field seems wrong and needs further examination
      #print STDERR "len2_1: $len2\n"; # if($len2);
	  #$len2=50 if($len2>1000);
	  #$len2=50 if($len2==1);
      #print STDERR "len2_2: $len2\n"; # if($len2);
	  #$len2=61;
	  
	  
      my $npos=$pos;
	  
      $rawbinary{"Pad"}{$counter}=substr($value,$pos,147); # !!!! Is this used again?

      my $component=unpack("s",msubstr($value,$pos+30,2,"component"));	
	  #print "Component: $component\n";
	  assertdata("Pad",$counter,"COMPONENT",$component) if($component>=0);

	  assertdata("Pad",$counter,"X",bmil2(msubstr($value,$pos+36,4,"X")));
	  assertdata("Pad",$counter,"Y",bmil2(msubstr($value,$pos+40,4,"Y")));
	  #print "Pad x: ".bmil2(substr($value,$pos+36,4))."\n";
	  #print "Pad y: ".bmil2(substr($value,$pos+40,4))."\n";
	  
      my $x1=-$xmove+bmil2mm(substr($value,$pos+36,4));
	  my $y1=$ymove-bmil2mm(substr($value,$pos+40,4));
  	  #MarkPoint($x1,$y1) if($counter eq 2);
	  $x1-=$componentatx{$component} if($component>=0 && defined($componentatx{$component}));
	  $y1-=$componentaty{$component} if($component>=0 && defined($componentaty{$component}));

      $x1=sprintf("%.5f",$x1);
	  $y1=sprintf("%.5f",$y1);
	  
      my $altlayer=unpack("C",msubstr($value,$pos+23,1,"altlayer"));
  	  assertdata("Pad",$counter,"LAYER",$altlayername{$altlayer});
	  #print "Altlayer: $altlayer\n";

      my $layer=mapLayer($altlayer) || "F.Cu"; $layer="*.Cu" if($altlayer==74);
	  
      #$layer.=" F.Mask F.Paste" if($layer=~m/[F\*]\.Cu/);
      #  $layer.=" B.Mask B.Paste" if($layer=~m/[B\*]\.Cu/);

	  my $sx=bmil2mm(msubstr($value,$pos+44,4,"sx")); # For Padmode=1, this is TOPXSIZE
	  my $sy=bmil2mm(msubstr($value,$pos+48,4,"sy")); # For Padmode=1, this is TOPYSIZE
  	  assertdata("Pad",$counter,"XSIZE",bmil2(substr($value,$pos+44,4)));
  	  assertdata("Pad",$counter,"YSIZE",bmil2(substr($value,$pos+48,4)));
      #print "sx: $sx sy: $sy\n";
	  
	  # Some Pads have TOPXSIZE, MIDXSIZE, BOTXSIZE, TOPYSIZE, ... instead of XSIZE+YSIZE, this is decided by PADMODE below.
	  
	  my $midxsize=bmil2mm(msubstr($value,$pos+52,4,"midxsize"));
	  my $midysize=bmil2mm(msubstr($value,$pos+56,4,"midysize"));
	  my $botxsize=bmil2mm(msubstr($value,$pos+60,4,"botxsize"));
	  my $botysize=bmil2mm(msubstr($value,$pos+64,4,"botysize"));
  	  #assertdata("Pad",$counter,"XSIZE",bmil2(substr($value,$pos+44,4)));
  	  #assertdata("Pad",$counter,"YSIZE",bmil2(substr($value,$pos+48,4)));
	  
	  
	  
	  
	  my $dir=unpack("d",msubstr($value,$pos+75,8,"direction")); 
	  assertdata("Pad",$counter,"ROTATION",enull(sprintf("%.14E",$dir)));
	  #print "Direction: $dir\n";
	  
	  my $holesize=bmil2mm(msubstr($value,$pos+68,4,"holesize"));
  	  assertdata("Pad",$counter,"HOLESIZE",bmil2(substr($value,$pos+68,4)));
	  #print "HoleSize: $holesize\n";
  
	  #my $holetype=unpack("C",msubstr($value,$pos+144,1,"holetype"));
  	  #assertdata("Pad",$counter,"HOLETYPE",$holetype); # Seems to be wrong
  
	  my $HOLEROTATION=unpack("d",msubstr($value,$pos+129,8,"holerotation")); 
	  assertdata("Pad",$counter,"HOLEROTATION",enull(sprintf("%.14E",$HOLEROTATION)));
      #print "Hole Rotation: $HOLEROTATION\n";
	  
	  my $mdir=($dir==0)?"":" $dir";
	  
	  my %typemap=("2"=>"rect","1"=>"circle","3"=>"oval","9"=>"roundrect","0"=>"Unknown");
	  my %typemapalt=("2"=>"RECTANGLE","1"=>"ROUND","3"=>"OCTAGONAL","0"=>"ROUND","9"=>"ROUNDEDRECTANGLE","4"=>"THERMALRELIEF","6"=>"POINT","7"=>"POINT"); 
	  my $otype=unpack("C",msubstr($value,$pos+72,1,"TOPOTYPE"));
	  my $midotype=unpack("C",msubstr($value,$pos+73,1,"MIDOTYPE")); # different shapes for different layers are not supported by KiCad
	  my $bototype=unpack("C",msubstr($value,$pos+74,1,"BOTOTYPE"));
  	  assertdata("Pad",$counter,"SHAPE",$typemapalt{$otype});
          my $type=$typemap{$otype};
          $type="roundrect" if($otype==1 && length($contents[5]));
	  #print "otype: $otype typemapalt: $typemapalt{$otype} type: $type\n";

	  if($otype eq "3")
	  {
	     print STDERR "WARNING: Octagonal pads are currently not supported by KiCad. We convert them to oval for now, please verify the PCB design afterwards. This can cause overlaps and production problems!\n" if(!defined($shownwarnings{'OCTAGONAL'}));
		 $shownwarnings{'OCTAGONAL'}++;
	  }
	  
	  $type="oval" if($type eq "circle" && $sx != $sy);
	  
	  
      my %platemap=("0"=>"FALSE","1"=>"TRUE");
      my $plated=$platemap{unpack("C",msubstr($value,$pos+83,1,"plated"))};	  
	  assertdata("Pad",$counter,"PLATED",uc($alttruth{unpack("C",substr($value,$pos+83,1))}));
      #print "Plated: $plated\n";
	  
	  my $onet=unpack("s",msubstr($value,$pos+26,2,"onet"));
  	  assertdata("Pad",$counter,"NET",$onet) if($onet>=0);
      my $net=$onet+2;	  
	  my $netname=$netnames{$net};
	  #print STDERR "ONet: $onet Net: $net NetName: $netname\n";
	  
	  my %soldermaskexpansionmap=("1"=>"Rule","2"=>"Manual");
  	  assertdata("Pad",$counter,"SOLDERMASKEXPANSIONMODE",$soldermaskexpansionmap{unpack("C",msubstr($value,$pos+125,1,"SolderMaskExpansionMode"))});
	  my $soldermaskexpansionmode=$soldermaskexpansionmap{unpack("C",msubstr($value,$pos+125,1,"SolderMaskExpansionMode"))}||"Rule";

	  my $PASTEMASKEXPANSIONMODE=unpack("C",msubstr($value,$pos+124,1,"PasteMaskExpansionMode"));
	  assertdata("Pad",$counter,"PASTEMASKEXPANSIONMODE",$altrule{$PASTEMASKEXPANSIONMODE});
	  my $PASTEMASKEXPANSION_MANUAL=bmil2mm(msubstr($value,$pos+109,4,"PasteMaskExpanionManual")); # AUTOGENERATED
      assertdata("Pad",$counter,"PASTEMASKEXPANSION_MANUAL",bmil2(substr($value,$pos+109,4))) if($PASTEMASKEXPANSION_MANUAL eq 2 && bmil2(substr($value,$pos+109,4)) ne "0mil");
	  
	  #print "PASTEMASKEXPANSION_MANUAL: $PASTEMASKEXPANSION_MANUAL\n";
	  
      #my $BOTXSIZE=bmil2mm(msubstr($value,$pos+60,4,"BotXsize")); # AUTOGENERATED
      #assertdata("Pad",$counter,"BOTXSIZE",bmil2(substr($value,$pos+60,4))); # Seems to be wrong
      #my $BOTYSIZE=bmil2mm(msubstr($value,$pos+64,4,"BotYsize")); # AUTOGENERATED
      #assertdata("Pad",$counter,"BOTYSIZE",bmil2(substr($value,$pos+64,4))); # Seems to be wrong
	  #TOPSIZEX/Y: 44/48/52/56
	  #MISIZEX/Y: 44/48/52/56
 
      my $CAG=bmil2mm(msubstr($value,$pos+97,4,"CAG")); # AUTOGENERATED
      assertdata("Pad",$counter,"CAG",bmil2(substr($value,$pos+97,4)));
      my $CCW=bmil2mm(msubstr($value,$pos+91,4,"CCW")); # AUTOGENERATED
      assertdata("Pad",$counter,"CCW",bmil2(substr($value,$pos+91,4)));
      my $CPC=bmil2mm(msubstr($value,$pos+105,4,"CPC")); # AUTOGENERATED
      assertdata("Pad",$counter,"CPC",bmil2(substr($value,$pos+105,4)));
      my $CPE=bmil2mm(msubstr($value,$pos+109,4,"CPE")); # AUTOGENERATED
      assertdata("Pad",$counter,"CPE",bmil2(substr($value,$pos+109,4)));
      my $CPR=bmil2mm(msubstr($value,$pos+101,4,"CPR")); # AUTOGENERATED
      assertdata("Pad",$counter,"CPR",bmil2(substr($value,$pos+101,4)));
      my $CSE=bmil2mm(msubstr($value,$pos+113,4,"CSE")); # AUTOGENERATED
      assertdata("Pad",$counter,"CSE",bmil2(substr($value,$pos+113,4)));
	  
      my $CEN=unpack("C",msubstr($value,$pos+95,1,"CEN")); # AUTOGENERATED
      assertdata("Pad",$counter,"CEN",$CEN);
      my $CPEV=unpack("C",msubstr($value,$pos+124,1,"CPEV")); # AUTOGENERATED
      assertdata("Pad",$counter,"CPEV",$CPEV);
      my $CPL=unpack("C",msubstr($value,$pos+117,1,"CPL")); # AUTOGENERATED
      assertdata("Pad",$counter,"CPL",$CPL) if($CPL);
      my $CSEV=unpack("C",msubstr($value,$pos+125,1,"CSEV")); # AUTOGENERATED
      assertdata("Pad",$counter,"CSEV",$CSEV);
	  
  	  assertdata("Pad",$counter,"SOLDERMASKEXPANSION_MANUAL",bmil2(msubstr($value,$pos+113,4,"SolderMaskExpansionManual"))) if($soldermaskexpansionmode eq "Manual");
  	  my $SOLDERMASKEXPANSION_MANUAL=bmil2mm(msubstr($value,$pos+113,4,"SolderMaskExpansionManual")); #Where is the SOLDERMASKEXPANSION_MANUAL stored?!? Is it in the CSE field?
	  
	  my $PADMODE=unpack("C",msubstr($value,$pos+85,1,"PadMode"));
	  assertdata("Pad",$counter,"PADMODE",$PADMODE);
	  my $differentpads=($sx ne $midxsize) || ($sy ne $midysize) || ($sx ne $botxsize) || ($sy ne $botysize) || ($otype ne $midotype) || ($otype ne $bototype);
	  if($PADMODE>0 && $differentpads)
	  {
	    my %padmodes=(0=>"Simple",1=>"Top-Middle-Bottom",2=>"Full Stack");
	    print STDERR "WARNING: Currently only the PadMode (Size and Shape) Simple is supported, ".$padmodes{$PADMODE}." is not supported by KiCad because KiCad uses the same Shape and Size on all layers.\n" if(!defined($shownwarnings{'SIMPLE'}));
		$shownwarnings{'SIMPLE'}++;
	  }
	  
	  #print "layer:$layer net:$net component=$component type:$type dir:$dir \n";
	  
	  
  	  #my $id=msubstr($value,$pos+2,16,"uniqueid"); # This seems to be very wrong, it is beyond the end of $value
      #    print "uniqueid: ".bin2hex($id)."\n" if(defined($id));

	  
	  #if(length($value)>=$pos && msubstr($value,$pos-4,4,"doubleaddition") eq "\x8B\x02\x00\x00")
	  #{
	  #  #print "Double addition detected\n";
	  #	$pos+=unpack("V",substr($value,$pos-4,4));
	  #} 
	  
	  
	  my $olayer=$altlayername{$altlayer}||"";
	  my $onettext=$onet>=0?"|NET=$onet":"";
	  my $dump=bin2hex(substr($value,$npos,143));
	  my $smem=$SOLDERMASKEXPANSION_MANUAL?"|SOLDERMASKEXPANSION_MANUAL=$SOLDERMASKEXPANSION_MANUAL":"";
	  print DOUT "$dump |RECORD=Pad$onettext|COMPONENT=$component|INDEXFORSAVE=$counter|SELECTION=FALSE|LAYER=$olayer|LOCKED=FALSE|POLYGONOUTLINE=FALSE|USERROUTED=TRUE|UNIONINDEX=0|SOLDERMASKEXPANSIONMODE=$soldermaskexpansionmode$SOLDERMASKEXPANSION_MANUAL|PASTEMASKEXPANSIONMODE=Rule|NAME=1|X=5511.1023mil|Y=3027.2441mil|XSIZE=39.3701mil|YSIZE=39.3701mil|SHAPE=RECTANGLE|HOLESIZE=0mil|ROTATION= 2.70000000000000E+0002|PLATED=TRUE|DAISYCHAIN=Load|CCSV=0|CPLV=0|CCWV=1|CENV=1|CAGV=1|CPEV=1|CSEV=$CSEV|CPCV=1|CPRV=1|CCW=25mil|CEN=4|CAG=$CAG|CPE=$CPE|CSE=$CSE|CPC=$CPC|CPR=20mil|PADMODE=0|SWAPID_PAD=|SWAPID_GATE=|&|0|SWAPPEDPADNAME=|GATEID=0|OVERRIDEWITHV6_6SHAPES=FALSE|DRILLTYPE=0|HOLETYPE=0|HOLEWIDTH=0mil|HOLEROTATION= 0.00000000000000E+0000|PADXOFFSET0=0mil|PADYOFFSET0=0mil|PADXOFFSET1=0mil|PADYOFFSET1=0mil|PADXOFFSET2=0mil|PADYOFFSET2=0mil|PADXOFFSET3=0mil|PADYOFFSET3=0mil|PADXOFFSET4=0mil|PADYOFFSET4=0mil|PADXOFFSET5=0mil|PADYOFFSET5=0mil|PADXOFFSET6=0mil|PADYOFFSET6=0mil|PADXOFFSET7=0mil|PADYOFFSET7=0mil|PADXOFFSET8=0mil|PADYOFFSET8=0mil|PADXOFFSET9=0mil|PADYOFFSET9=0mil|PADXOFFSET10=0mil|PADYOFFSET10=0mil|PADXOFFSET11=0mil|PADYOFFSET11=0mil|PADXOFFSET12=0mil|PADYOFFSET12=0mil|PADXOFFSET13=0mil|PADYOFFSET13=0mil|PADXOFFSET14=0mil|PADYOFFSET14=0mil|PADXOFFSET15=0mil|PADYOFFSET15=0mil|PADXOFFSET16=0mil|PADYOFFSET16=0mil|PADXOFFSET17=0mil|PADYOFFSET17=0mil|PADXOFFSET18=0mil|PADYOFFSET18=0mil|PADXOFFSET19=0mil|PADYOFFSET19=0mil|PADXOFFSET20=0mil|PADYOFFSET20=0mil|PADXOFFSET21=0mil|PADYOFFSET21=0mil|PADXOFFSET22=0mil|PADYOFFSET22=0mil|PADXOFFSET23=0mil|PADYOFFSET23=0mil|PADXOFFSET24=0mil|PADYOFFSET24=0mil|PADXOFFSET25=0mil|PADYOFFSET25=0mil|PADXOFFSET26=0mil|PADYOFFSET26=0mil|PADXOFFSET27=0mil|PADYOFFSET27=0mil|PADXOFFSET28=0mil|PADYOFFSET28=0mil|PADXOFFSET29=0mil|PADYOFFSET29=0mil|PADXOFFSET30=0mil|PADYOFFSET30=0mil|PADXOFFSET31=0mil|PADYOFFSET31=0mil|PADJUMPERID=0\n";
	  
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
          my $roundness=length($contents[5])>568?unpack("C",substr($contents[5],568,1)):0;
	  #print "Roundness: $roundness\n" if($type eq "roundrect");

	  my $tp=($holesize==0)?"smd":$plated eq "TRUE"?"thru_hole":"np_thru_hole";
	  my $addparams=($holesize==0)?"":" (drill $holesize) ";
	  $netname=~s/ //g;
 	  my $nettext=($net>1)?"(net $net \"$netname\")":"";
      my $oposhex=sprintf("%X",$opos);
	  #$component=$uniquemap{"Pad"}{$counter} if($component==-1);
	  #print "Component: $component\n";
	  $addparams.=" (roundrect_rratio ".($roundness/200.0).") " if($type eq "roundrect");
	  
	  if($annotate)
	  {
	    $pads{$component}.="#1309 counter:$counter opos:$opos(0x$oposhex) otype:$otype onet:$onet hole:$holesize\n";
            foreach(0 .. 5)
            {
              $pads{$component}.="#$_:".bin2hex($contents[$_])."\n";
            }
	  }
      $name=~s/\\//g;
	  $pads{$component}.=<<EOF
    (pad "$name" $tp $type (at $x1 $y1$mdir) (size $sx $sy) $addparams
      (layers $layer) $nettext
    )
EOF
;

      #print "Component: $component\n$pads{$component}\n";
	  
	  #print "Checking... pos:$pos\n";
	  if((length($value)>$pos+0x1e0) && substr($value,$pos,1) ne "\x02" && substr($value,$pos+0x1e0,1) eq "\x02")
	  {
	     print "Seems we should skip 0x1e0 bytes\n";
		 $pos+=0x1e0;
      }
	  
	  
	  if($pos != $tpos)
	  {
	    #print "POS should be $tpos but it is currently $pos\n";
	  }
	  $pos=$tpos;
	  
	  
	  $counter++;
	  
	}
	#close DOUT;

	
	print HOUT "Dump: $filename\n".dumpAnnotatedHex($value);

	
	#print HOUT "</pre></body></html>";
	#close HOUT;
  
}



  


# Looking, whether we have to unpack the files first:
# The current behaviour is that additional new or modified files are not processed
my @files=glob('"*/Root Entry/Board6/Data.dat"');
if(!scalar(@files))
{
  print "No unpacked .PcbDoc documents found. Trying to unpack it:\n";
  # Where can we find the unpack.pl? Should we run it from the same directory, convertpcb.pl comes from
  my $path=abs_path($0); $path=~s/convertpcb\.pl$//;
  #print STDERR "$path\n";
  system "$path/unpack.pl";
  @files=glob('"*/Root Entry/Board6/Data.dat"')
}

# Now we start handling all the PCB files that were unpacked by unpack.pl already:
my $filecounter=0;
foreach my $filename(@files)
{
  $filecounter++;
  print "Handling $filename\n";
  my $short=$filename; $short=~s/\/Root Entry\/Board6\/Data\.dat$//;


  if($short=~m/CrypTech/i)
  {
    print "Detected Cryptech board, aligning for Gerber comparison\n";
    $xmove=199.898;
    $ymove=64.516;
  }

  
  our %verify=();
  %result=();
  our @asciilines=();
  our %positions=();
  
  %shownwarnings=();
  
  # assertdata asserts that a parsed binary field has been parsed properly, by comparing it to the ascii variant.
  sub assertdata
  {
    my ($record,$line,$name,$value)=@_;
    return if(!defined($verify{$record}) || !defined($verify{$record}{$line}));
	print STDERR "Undefined value in $record $line $name\n" if(!defined($value));
    $result{$record}{$line}{$name}=$value;
	return if($name=~m/^(UNIONINDEX|GROUPNUM|COUNT)$/);
	my $vvalue=defined($verify{$record}{$line}{$name})?$verify{$record}{$line}{$name}:"";
	$vvalue=~s/\s*$//; $value=~s/\s*$//;
	my $good=$value eq $vvalue?1:0; 
    $cgoodbad{$record}{$name}{$good}++;
	print "assert: $record $line $name $value".($good?"=":"<>").($vvalue||"")."\n" if(!$good);
  }
 
  # Reading the ASCII version of the .PcbDoc into %verify if it exists, so that we can compare the binary version against it
  my $asciifn=$short; $asciifn=~s/^bin-//; $asciifn="ASCII-$asciifn";
  print "$asciifn.PcbDoc exists?\n";
  if(-r "$asciifn.PcbDoc")
  {
    print "Yes! Loading verification values\n";
    my $ascii=readfile("$asciifn.PcbDoc");
	@asciilines=split "\n",$ascii;
	
	my %linenos=();
	
	foreach my $line (@asciilines)
	{
      my @a=split '\|',$line;
	  my %d=();
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
	  if(defined($d{'RECORD'}))
	  {
	    my $lineno=$linenos{$d{'RECORD'}}++;
		$lineno=$d{'INDEXFORSAVE'} if(defined($d{'INDEXFORSAVE'}));
		foreach(keys %d)
		{
	      $verify{$d{'RECORD'}}{$lineno}{$_}=$d{$_};
		  #print "\$verify{$d{'RECORD'}}{$lineno}{$_}=$d{$_};\n";
		}
      }
	  
	}
  
  }

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
  # At first we extract Layer-information and other Board-related information from the Board file
  HandleBinFile($filename,"",0,0,sub {
    my %d=%{$_[0]};
	foreach(sort keys %d)
	{
	  #assertdata("Board",$_[3],$_,$d{$_});
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
		#print "$_ $1 next -> $d{$_}\n";
	  }
      if($_=~m/^LAYER(\d+)PREV$/)
	  {
	    $layerprev{$1}=$d{$_};
		$activelayer{$1}=1 if($d{$_});
		#print "$_ $1 prev -> $d{$_}\n";
	  }
	  if($_=~m/^TRACKWIDTH$/)
	  {
	    #print "Track Width: $d{$_}\n";
		$trackwidth=$d{$_};
	  }
	  if($_=~m/^VERSION$/)
	  {
	    #print "Version: $d{$_}\n";
		$version=$d{$_};
	  }
	}
  }); # Board
  
  # We search for the first and last layer
  our $firstlayer=0;
  our $lastlayer=0;
  our @layersorder=();
  foreach(sort keys %activelayer)
  {
    next if($_>=33 && $_<=38);
    $firstlayer=$_ if($layerprev{$_}==0 && $layernext{$_}!=0);
	$lastlayer=$_ if($layerprev{$_}!=0 && $layernext{$_}==0);
	#print "this: $_ prev:$layerprev{$_} next:$layernext{$_} first:$firstlayer last:$lastlayer\n";
  }
  #print "Firstlayer: $firstlayer\nLastlayer: $lastlayer\n";
  
  # Now we create a list of the layers in the correct order
  my $thislayer=$firstlayer;
  while($thislayer!=0)
  {
	push @layersorder,$thislayer;
	$thislayer=$layernext{$thislayer};
  }
  #print "Layers: ".join(",",@layersorder)."\n";
  #print "Active layers: ".scalar(keys @layersorder)."\n";
    

  my $layers="";
  # If needed, you can display a list of all the layers and their names 
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
  
  # We extract the filenames and rotation information for the 3D models:
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

  # We extract the references between the primitives(Pads,...) and the Components:
  our %uniquemap=();
  HandleBinFile("$short/Root Entry/UniqueIDPrimitiveInformation/Data.dat","",0,0,sub 
  { 
	$uniquemap{$_[0]{'PRIMITIVEOBJECTID'}}{$_[0]{'PRIMITIVEINDEX'}}=$_[0]{'UNIQUEID'};
	#print "$_[0]{'PRIMITIVEOBJECTID'}/$_[0]{'PRIMITIVEINDEX'} -> $_[0]{'UNIQUEID'}\n";
  });
  
  # Now we extract the DRC design rules, which we will have to assign to zones, ...
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
	  #print "Rule $rulekind $name gives clearance $clearance\n";
	  $rules{$name}=$clearance;
	}
	if(defined($gap))
	{
	  #print "Rule $rulekind $name gives gap $gap\n";
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
  
  # Analyzing the Net-Classes, currently ignoring all other classes
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
	assertdata("Class",$_[3],"RECORD","Class");
	assertdata("Class",$_[3],"INDEXFORSAVE",sprintf("%d",$_[3]));
    #assertdata("Class",$_[3],$_,$_[0]{$_}) foreach(keys %{$_[0]});
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

  # Now we start to output the PCB file for KiCad
  print "Writing PCB to $short.kicad_pcb\n";
  open OUT,">$short.kicad_pcb";

  # We create the Net-list, $nets will be embedded into the file-header
  our $nets="";
  our $nnets=2;
  %netnames=("1"=>"Net1");
  HandleBinFile("$short/Root Entry/Nets6/Data.dat","",0,0, sub 
  { 
    my $line=$_[3]+2;
	$nnets=$line+1;
    my $name=$_[0]{'NAME'};
	assertdata("Net",$_[3],"RECORD","Net");
	assertdata("Net",$_[3],"ID",$_[3]);
	assertdata("Net",$_[3],"INDEXFORSAVE",$_[3]);
	assertdata("Net",$_[3],$_,$_[0]{$_}) foreach(keys %{$_[0]});
	$name=~s/((.\\)+)/\~$1\~/g; $name=~s/(.)\\/$1/g; 
	$name=~s/\\//g;
        $name=~s/ //g;
	$netnames{$line}=$name;
    $nets.= "  (net $line \"$name\")\n";
  });


  my $clearance=$rules{'Clearance'} || "0.127";
  my $tracewidth=mil2mm($trackwidth);

  # We create the Layer-list, $layertext will be embedded into the file-header
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
    (visible_elements 7FFFF77F)
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
    print OUT " (net_class \"$class\" \"$class\"\n";
	print OUT <<EOF
	(clearance $clearance)
    (trace_width $tracewidth)
    (via_dia 0.889)
    (via_drill 0.635)
    (uvia_dia 0.508)
    (uvia_drill 0.127)
EOF
;
    foreach my $name(sort keys %{$netclass{$class}})
    {
      $name=~s/((.\\)+)/\~$1\~/g; $name=~s/(.)\\/$1/g;
      $name=~s/\\//g;
	  $name=~s/ //g;
      print OUT "    (add_net \"$name\")\n"
    }
    print OUT "  )\n";
  }


  
  # Mapping the original Layer Numbers to KiCad Layer names
  our %layermap=(
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
  "57"=>"Edge.Cuts", # For Fernvale, this should be mapped to F.Fab, for EDA-02530 this should be Edge.Cuts
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
  
  # Adding internal copper layers
  foreach(1 .. scalar(@layersorder)-2)
  {
     #if(defined($layermap{$layersorder[$_]}) && $layermap{$layersorder[$_]} ne "In$_.Cu")
	 #{
	 #  #print "Changing $_ $layersorder[$_] from old value $layermap{$layersorder[$_]} to In$_.Cu\n";
	 #}
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
	  #print "Found plane $1\n";
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
  $layermap{"MECHANICAL15"}=$layermap{70};
  $layermap{"MECHANICAL1"}="Eco1.User";
  $layermap{"MECHANICAL2"}="Eco1.User";
  $layermap{"MECHANICAL3"}="Eco1.User";
  $layermap{"MECHANICAL4"}="Eco1.User";
  $layermap{"MECHANICAL5"}="Eco1.User";
  $layermap{"MECHANICAL6"}="Eco1.User";
  $layermap{"MECHANICAL7"}="Eco1.User";
  $layermap{"MECHANICAL8"}="Eco1.User";
  $layermap{"MECHANICAL9"}="Eco1.User";
  $layermap{"MECHANICAL10"}="Eco1.User";
  $layermap{"MECHANICAL11"}="Eco1.User";
  $layermap{"55"}="Cmts.User";
  $layermap{"CONNECT"}="Eco1.User"; # This seems to be used only for Regions which are currently not needed
  
  # Dumping the resulting layer map
  foreach(sort keys %layermap)
  {
    #print "SORT: $_ -> $layermap{$_}\n";
  }
 
  %pads=();
  my %padrotate=();
  our %unmappedLayers=();
  our %usedlayers=();
  our %layererrors=();
  
  
  # This function maps the Layer numbers or names to KiCad Layernames
  # It also logs which Layers are effectively used and which layers are needed but not mapped yet.
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
      print STDERR "WARNING: No mapping for Layer ".$_[0]." defined!\n" ;
	  $layererrors{$_[0]}=1;
	}
	return $layermap{$_[0]}; 
  }

  #Mapping the Standard components to KiCad Standard Components:
  our %A2Kwrl=(
    "Chip Diode - 2 Contacts.PcbLib/CD1608-0603"=>"Capacitors_SMD.3dshapes/C_0603.wrl", #"smd.3dshapes/Capacitors/C0603.wrl",
    "Chip Diode - 2 Contacts.PcbLib/CD2012-0805"=>"Capacitors_SMD.3dshapes/C_0805.wrl", #"smd.3dshapes/Capacitors/C0805.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC1005N"=>"Capacitors_SMD.3dshapes/C_0402.wrl", #"smd.3dshapes/Capacitors/C0402.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC1608N"=>"Capacitors_SMD.3dshapes/C_0603.wrl", #"smd.3dshapes/Capacitors/C0603.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC2012N"=>"Capacitors_SMD.3dshapes/C_0805.wrl", #"smd.3dshapes/Capacitors/C0805.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC3216N"=>"Capacitors_SMD.3dshapes/C_1206.wrl", #"smd.3dshapes/Capacitors/C1206.wrl",
    "Chip_Capacitor_N.PcbLib/CAPC3225N"=>"Capacitors_SMD.3dshapes/C_1210.wrl", #"smd.3dshapes/Capacitors/C1210.wrl",
    "Chip_Resistor_N.PcbLib/RESC1005N"=>"Resistors_SMD.3dshapes/R_0402.wrl", #"smd.3dshapes/resistors/R0402.wrl",
    "Chip_Resistor_N.PcbLib/RESC1608N"=>"Resistors_SMD.3dshapes/R_0603.wrl", #"smd.3dshapes/resistors/R0603.wrl",
    "Chip_Resistor_N.PcbLib/RESC2012N"=>"Resistors_SMD.3dshapes/R_0805.wrl", #"smd.3dshapes/resistors/R0805.wrl",
    "Chip_Resistor_N.PcbLib/RESC3216N"=>"Resistors_SMD.3dshapes/R_1206.wrl", #"smd.3dshapes/resistors/R1206.wrl",
    "Miscellaneous Connectors.IntLib/HDR2X20"=>"Pin_Headers.3dshapes/Pin_Header_Straight_2x20.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X4"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x4.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X6"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x6.wrl",
    "Miscellaneous Connectors.IntLib/HDR1X8"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x8.wrl",  
    "Miscellaneous Connectors.IntLib/HDR2X8"=>"Pin_Headers.3dshapes/Pin_Header_Straight_2x8.wrl",
    "NSC LDO.IntLib/MP04A_N"=>"smd.3dshapes/SOT223.wrl",
    "National Semiconductor DAC.IntLib/MUA08A_N"=>"smd.3dshapes/smd_dil/msoic-8.wrl",
    "SOIC_127P_N.PcbLib/SOIC127P600-8N"=>"smd.3dshapes/smd_dil/psop-8.wrl",
    "SOP_65P_N.PcbLib/SOP65P640-16N"=>"smd.3dshapes/smd_dil/ssop-16.wrl",
    "SOT23_5-6Lead_N.PcbLib/SOT23-5AN"=>"smd.3dshapes/SOT23_5.wrl",
    "TSOP_65P_N.PcbLib/TSOP65P640-24AN"=>"smd.3dshapes/smd_dil/tssop-24.wrl",
    "commonpcb.lib/CAPC0603N_B"=>"Capacitors_SMD.3dshapes/C_0603.wrl", #"smd.3dshapes/Capacitors/C0603.wrl",
    "commonpcb.lib/CAPC1608N_HD"=>"Capacitors_SMD.3dshapes/C_1608.wrl", #"smd.3dshapes/Capacitors/C1608.wrl",
    "commonpcb.lib/SWITCH_TS-1187A"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/USB_TYPEA_TH_SINGLE"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/HAOYU_TS_1185A_E"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x4.wrl",
    "commonpcb.lib/JST_S3B_EH"=>"Pin_Headers.3dshapes/Pin_Header_Straight_1x3.wrl",
	);
		
		
  #Parsing the Components into the hashes for later use
  our $componentid=0;
  %componentatx=();
  %componentaty=();
  our %componentlayer=();
  our %componentrotate=();
  our %kicadwrl=();
  our %componenthandled=();
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
	$componentrotate{$componentid}=sprintf("%.f",$d{'ROTATION'});
	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'PATTERN'};
#	my $reference=$d{'SOURCEFOOTPRINTLIBRARY'}."/".$d{'SOURCELIBREFERENCE'};
	
	#print "ref: $reference ".$A2Kwrl{$reference}." comp:$componentid\n";
	$kicadwrl{$componentid}=$A2Kwrl{$reference}; # !!! XXX A2Kwrl Mapping temporarily disabled 
	
	$nameon{$componentid}=$d{'NAMEON'};
	$commenton{$componentid}=$d{'COMMENTON'};
	
	assertdata("Component",$_[3],"RECORD","Component");
	assertdata("Component",$_[3],"ID",$_[3]);
	assertdata("Component",$_[3],"INDEXFORSAVE",$_[3]);
	assertdata("Component",$_[3],$_,$_[0]{$_}) foreach(keys %{$_[0]});
	
	if(defined($kicadwrl{$componentid}))
	{
	  #$newa2k{" \"$reference\"=>\"".$A2Kwrl{$reference}."\",\n"}=1;
	}
	else
	{
	  #print "    \"$reference\"=>\".wrl\",\n" if(!defined($kicadwrlerror{$reference}));
	  $kicadwrlerror{$reference}=1;
	}
    $componentid++;
  });


  #Converting the Pads  
  #The output is collected in %pads, which is later on filled into the output file in the ComponentBodies Section.
  #HandleBinFile("$short/Root Entry/Pads6/Data.dat","\x02",0,0, sub 
  {
    %linebreaks=(); # These must be initialized before the parsing since we might handle several files
    %bytelabels=();
    print "Pads6...\n";
    my $value=readfile("$short/Root Entry/Pads6/Data.dat");
    #$value=~s/\r\n/\n/gs;
	
	HandlePads($value,$short);	
  }

  our %ComponentNotFoundErrors=();
  #Converting Component Bodies
  #The results are also added to %pads
  HandleBinFile("$short/Root Entry/ComponentBodies6/Data.dat","",23,16, sub 
  { 
    print OUT "#ComponentBodies#".escapeCRLF($_[3]).": ".bin2hexLF($_[2])." ".escapeCRLF($_[1])."\n" if($annotate);

    my %d=%{$_[0]};
	my $header=$_[2];
	my $component=unpack("s",substr($header,12,2));
	
	assertdata("ComponentBody",$_[3],"RECORD","ComponentBody");
	assertdata("ComponentBody",$_[3],"COMPONENT",$component) if($component>=0);
	#$rawbinary{"ComponentBody"}{$_[3]}=$_[2];
	print OUT "#\$pads{$component}\n" if($annotate);
	#print "Component:$component $pads{$component}-\n";
	my $id=$d{'MODELID'}||0;
	my $atx=mil2mm($d{'MODEL.2D.X'}||0);$atx-=$xmove;
	my $aty=mil2mm($d{'MODEL.2D.Y'}||0);$aty=$ymove-$aty;
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
	if(!defined($modelname{$d{'MODELID'}||0}))
	{
	  #print "MODELID: $d{'MODELID'}\n";
	}

	my $ident=""; $ident.=pack("C",$_) foreach(split(",",$d{'IDENTIFIER'}||""));
	
	#my $rot=(($modelrotx{$id}||0)+$d{'MODEL.3D.ROTX'})." ".(($modelroty{$id}||0)+$d{'MODEL.3D.ROTY'})." ".(($modelrotz{$id}||0)+$d{'MODEL.3D.ROTZ'});
	my $rot=((360-($d{'MODEL.3D.ROTX'}||0))." ".(360-($d{'MODEL.3D.ROTY'}||0))." ".(360-($d{'MODEL.3D.ROTZ'}||0)));
	#my $rot=(($modelrotx{$id}||0))." ".(($modelroty{$id}||0))." ".(($modelrotz{$id}||0));
	
	my $mdz=($modeldz{$id}||0)/10000000;
	my $cdz=mil2mm($d{'MODEL.3D.DZ'}||0); 
	my $standoff=mil2mm($d{'STANDOFFHEIGHT'}||0);
    #print "mdz:  ".($modeldz{$id}||0)." -> $mdz MODEL.3D.DZ: $d{'MODEL.3D.DZ'} -> $cdz standoff: *$d{STANDOFFHEIGHT}* -> $standoff $modelname{$id}\n" if($mdz!=0);
	my $dz=$mdz;
	
	my $wrl=(defined($modelwrl{$id}) && -f $modelwrl{$id}) ? $modelwrl{$id} : undef;
	mkdir "wrl";
	if(defined($stp)&& defined($wrl))
	{
	  $stp=~s/\w:\\.*\\//;
	  #print "Copying $wrl to wrl/$stp.wrl\n";
	  writefile("wrl/$stp.wrl",readfile($wrl));
	}
	$wrl="wrl/$stp.wrl" if(defined($stp));
	
	#print "component: $component wrl: $wrl\n";
	
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
          #print "wrl: $wrl\n";		  
		  $lfak=1;
		}
		#print "component:$component wrl:$wrl\n";		
	
	    $componentbodyavailable{$component}=1;
	
        if(defined($modelhints{$wrl}))
        {
		  #print "OK: $wrl\n";
          $pads{$component}.="#921 component:$component id:$id nr:$_[3]\n#".join("|",map { "$_=$_[0]{$_}" } sort keys %{$_[0]})." 0:".bin2hexLF($header)."\n    (model \"$wrl\"\n".$modelhints{$wrl}."\n";
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
	  print "NOT FOUND: $stp.wrl\n" if(defined($stp) && !defined($ComponentNotFoundErrors{$stp}));
	  $ComponentNotFoundErrors{$stp||""}++;
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
  
  print OUT "#Now handling Shape Based Bodies ...\n" if($annotate);
  # The results are also added to the %pads and only printed later on
  HandleBinFile("$short/Root Entry/ShapeBasedComponentBodies6/Data.dat","\x0c",0,0, sub 
  { 
    my $value=$_[1];
    print OUT "#ShapeBasedComponentBodies#".escapeCRLF($_[3]).": ".bin2hexLF($value)."\n" if($annotate);
    #print "#ShapeBasedComponentBodies#".$_[3]."\n" if($annotate);
	my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean
	my $component=unpack("s",substr($value,7,2));
	#print "Shape Component: $component\n";
	assertdata("ShapeBasedComponentBody",$_[3],"COMPONENT",$component);
	$rawbinary{"ShapeBasedComponentBody"}{$_[3]}=$_[2];
    print OUT "# ".bin2hexLF($unknownheader)."\n" if($annotate);
    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
	assertdata("ShapeBasedComponentBody",$_[3],"TEXT",$text);
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
	
	my $ident=""; $ident.=pack("C",$_) foreach(split(",",$d{'IDENTIFIER'}||""));
	
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

	my $wrl="wrlshp/".substr($d{'MODELID'}||"",0,14).".wrl"; $wrl=~s/[\{\}]//g;

    my $rot=(360-($componentrotate{$component} || "0"))*$pi/180.0;
	my $modeltype=$d{'MODEL.MODELTYPE'} || -1;
    if($modeltype == 0) # Extruded Polygon
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
	  #print "Extruding polygon... $pz\n";
	  if($good)
	  {
	    my $addition=ExtrudedPolygon("0 0 $pz","0 0 1  $rot","$fak $fak $fak",$color,"1",$sz,\@poly);
	    $shapes{$wrl}.=$addition."," if(defined($addition));
	  }
	}
    $shapes{$wrl}="" unless(defined($shapes{$wrl}));
	
	if($modeltype == 1) #Cone
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=mil2mm($d{'STANDOFFHEIGHT'}); #$pz=~s/mil//; $pz/=100; 
	  my $sz=mil2mm($d{'OVERALLHEIGHT'})-$pz; #; $sz=~s/mil//; $sz/=100; $sz-=$pz;
      #$shapes{$wrl}.=Cone("0 0 0 ","0 0 0  0","1 1 1",$color,"1",$sz,"3").",";
	}

    if($modeltype == 2) #Cylinder
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=$faktor*100; $px=-$px;
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=$faktor*100; $py=-$py;
      my $pz=$d{'STANDOFFHEIGHT'};$pz=~s/mil//; $pz/=100; 
	  my $cx=($componentatx{$component}||0)/100;
	  my $cy=($componentaty{$component}||0)/100;
	  my $dx=$px+$cx; $dx*=-$faktor;
	  my $dy=$py-$cy; $dy*=-$faktor;
	  my $h=mil2mm($d{'MODEL.CYLINDER.HEIGHT'});  #$h=~s/mil//; $h/=100; $h=sprintf("%.7f",$h);
	  my $r=mil2mm($d{'MODEL.CYLINDER.RADIUS'});  #$r=~s/mil//; $r/=100; $r=sprintf("%.7f",$r);
	  #print "Cylinder: px: $d{'MODEL.2D.X'} -> $px , $componentatx{$component} -> $cx , $dx py: $d{'MODEL.2D.Y'} -> $py , $componentaty{$component} -> $cy , $dy ident: $ident\n";
      $shapes{$wrl}.=Cylinder("$dx $dy 0 ","0 0 1  $rot","$fak $fak $fak",$color,"1",$r,$h).",";
	}

    if($modeltype == 3) # Sphere
	{
	  my $px=$d{'MODEL.2D.X'};$px=~s/mil//; $px/=100; 
	  my $py=$d{'MODEL.2D.Y'};$py=~s/mil//; $py/=100; 
      my $pz=$d{'STANDOFFHEIGHT'};$pz=~s/mil//; $pz/=100; 
	  
	  #my $h=$d{'MODEL.CYLINDER.HEIGHT'};$h=~s/mil//; $h/=100; $h=sprintf("%.7f",$h);
	  #my $r=$d{'MODEL.CYLINDER.RADIUS'};$r=~s/mil//; $r/=100; $r=sprintf("%.7f",$r);
      $shapes{$wrl}.=Sphere("0 0 0 ","0 0 0  0","1 1 1",$color,"1","1",$pz).",";
	}
    $rot=$componentrotate{$component} || "0";
    $pads{$component}.=<<EOF
#1365
	(model "$wrlprefix/$wrl"
      (at (xyz 0 0 0))
      (scale (xyz 1 1 1))
      (rotate (xyz 0 0 $rot))
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
    print OUT "#Components#".escapeCRLF($_[3]).": ".escapeCRLF($_[1])."\n" if($annotate);
	print OUT "#\$pads{$componentid}\n" if($annotate);
	#print "Component: $componentid ".($pads{$componentid}||"")."\n";
	my $atx=mil2mm($d{'X'});$atx-=$xmove;
	my $aty=mil2mm($d{'Y'});$aty=$ymove-$aty;
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
	my $rot=sprintf("%.f",$d{'ROTATION'});
    my $stp=$d{'SOURCEDESIGNATOR'};
#	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'SOURCELIBREFERENCE'};
	my $reference=($d{'SOURCEFOOTPRINTLIBRARY'}||"")."/".$d{'PATTERN'};
	
	my $sourcelib=($d{'SOURCEFOOTPRINTLIBRARY'}||"");
	#SOURCELIBREFERENCE

	#print "Component $componentid body available: ".(defined($componentbodyavailable{$componentid})?"Yes":"No")."\n";
	if(!defined($componentbodyavailable{$componentid}))
	{
	  #print "Not available, pads: ".defined($pads{$componentid})." model: ".(($pads{$componentid}||"")=~m/\(model/)."\n";
	  if(defined($pads{$componentid}) && $pads{$componentid}=~m/\(model/)
	  {
		  #print "Where did the model come from? componentid: $componentid\n"; # !!! TODO
	  }
	  #print "kicad: ".defined($kicadwrl{$componentid})." ".($pads{$componentid}=~m/\(model/)."\n";
	  #print "pad: ".$pads{$componentid}."\n----\n";
	  if(defined($kicadwrl{$componentid}) && !(($pads{$componentid}||"")=~m/\(model/))
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
		  #print "NOK: *$wrl*\n";
	      $pads{$componentid}.=<<EOF
#991		  
	(model "$wrl"
      (at (xyz 0 0 0))
      (scale (xyz 1 1 1))
      (rotate (xyz 0 0 0))
#	       (rotate (xyz 0 0 $rot))
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
		
	#print "Componentid: $componentid UniqueID: $d{'UNIQUEID'}\n";
		
    my $pad=pad3dRotate($pads{$componentid}||$pads{$d{'UNIQUEID'}||""}||"",$rot);
	#print "pad: $pad\n";
    if(defined($pads{$componentid}) && $pads{$componentid}=~m/\.\/wrl\//)
	{
	  #print "Rewriting scale\n";
	  $pad=~s/\(scale\s*\(xyz 1 1 1\)\)/(scale (xyz $fak $fak $fak))/sg;
	  #print "Result: $pad\n";
	}
	

	
	#print "stp -> $rot\n";
	# We have to handle (attr smd) and (tag ...) here ...
	my $PATTERN=$d{'PATTERN'}; $PATTERN=~s/"/\\"/g;
	my $SOURCEDESCRIPTION=$d{'SOURCEDESCRIPTION'}||""; $SOURCEDESCRIPTION=~s/"/\\"/g;
	my $FOOTPRINTDESCRIPTION=$d{'FOOTPRINTDESCRIPTION'}||""; $FOOTPRINTDESCRIPTION=~s/"/\\"/g;
	my $SOURCEDESIGNATOR=$d{'SOURCEDESIGNATOR'}||""; $SOURCEDESIGNATOR=~s/"/\\"/g;
    print OUT <<EOF
 (module "$PATTERN" (layer $layer) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at $atx $aty)
    (path /539EEC0F)
    (attr smd)
	(fp_text reference "$stp" (at 0 0) (layer F.SilkS) hide
      (effects (font (thickness 0.05)))
    )
    (fp_text value "$SOURCEDESIGNATOR" (at 0 0) (layer F.SilkS)
      (effects (font (thickness 0.05)))
    )
	(fp_text value "$SOURCEDESCRIPTION" (at 0 0) (layer F.SilkS) hide
      (effects (font (thickness 0.05)))
    )

	$pad
  )
EOF
if(defined($stp)); # Here we end up with new Altium files

    $componentid++;
  });


# This is a workaround to create a "DEFAULT" component for component-less pads, since component-less pads are not supported by KiCad
if(defined($pads{"-1"}))
{
  my $pad=$pads{"-1"};
  print OUT <<EOF
 (module "DEFAULT" (layer F.Cu) (tedit 4289BEAB) (tstamp 539EEDBF)
    (at 0 0 )
    (path /539EEC0F)
    (attr smd)
	$pad
  )
EOF
  ;
}  
  
  HandleBinFile("$short/Root Entry/Arcs6/Data.dat","\x01",0,0,\&HandleArc);

  
  
  my $count=0;
  HandleBinFile("$short/Root Entry/Vias6/Data.dat","\x03",0,0, sub 
  { 
    my $value=$_[1];
	$rawbinary{"Via"}{$_[3]}=$_[1];
	print OUT "#Vias#".escapeCRLF($_[3]).": ".bin2hexLF($value)."\n" if($annotate);
        my $debug=($count<100);
        my $x=sprintf("%.5f",-$xmove+bmil2mm(substr($value,13,4)));
	assertdata("Via",$_[3],"X",bmil2(substr($value,13,4)));
	my $y=sprintf("%.5f",+$ymove-bmil2mm(substr($value,17,4)));
	assertdata("Via",$_[3],"Y",bmil2(substr($value,17,4)));
	my $width=bmil2mm(substr($value,21,4));
	assertdata("Via",$_[3],"DIAMETER",bmil2(substr($value,21,4)));
	my $HOLESIZE=bmil2mm(substr($value,25,4));
	assertdata("Via",$_[3],"HOLESIZE",bmil2(substr($value,25,4)));
	
	my $layer1="F.Cu"; # mapLayer(unpack("C",substr($value,0,1))); # || "F.Cu"; # Since Novena does not have any Blind or Buried Vias
	my $layer2="B.Cu"; # mapLayer(unpack("C",substr($value,1,1))); # || "B.Cu";
	my $net=unpack("s",substr($value,3,2))+2;
	assertdata("Via",$_[3],"NET",unpack("s",substr($value,3,2)));
	
	my $CAGV=unpack("C",substr($value,40,1)); # AUTOGENERATED, CAGV=CCSV=CENV ?!?
    assertdata("Via",$_[3],"CAGV",$CAGV);
	my $CCSV=unpack("C",substr($value,40,1)); # AUTOGENERATED  
    assertdata("Via",$_[3],"CCSV",$CCSV);
	#my $CEN=unpack("C",substr($value,23,1)); # AUTOGENERATED Seems to be wrong
    #assertdata("Via",$_[3],"CEN",$CEN);
	my $CENV=unpack("C",substr($value,40,1)); # AUTOGENERATED
    assertdata("Via",$_[3],"CENV",$CENV);
	
    my $UNIONINDEX=unpack("C",substr($value,70,1)); # AUTOGENERATED
	assertdata("Via",$_[3],"UNIONINDEX",$UNIONINDEX);

	
	#print "Layer: $layer1 -> $layer2\n";
	#print "Koordinaten:\n" if($debug);
	#print "x:$x y:$y width:$width\n" if($debug);
	my $addparams="";
	$addparams.="(drill $HOLESIZE) " if($HOLESIZE);
	print OUT "  (via (at $x $y) (size $width) (layers $layer1 $layer2) (net $net)$addparams)\n";


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
	  #print "count: $count Firstlayer: $firstlayer Lastlayer: $lastlayer ".bin2hex($value)."\n"; # if(!($firstlayer==0 && $lastlayer==9));
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
	      #print "DEBUG: ".bin2hexLF($value)."\n\n";
		}
	  }
	}
	$count++;
  });
  
  $count=0; 
  
  
  HandleBinFile("$short/Root Entry/Polygons6/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	print OUT "#Polygons#".escapeCRLF($_[3]).": ".escapeCRLF($_[1])."\n" if($annotate);
	my $counter=$_[3];
	my $width=mil2mm($d{'TRACKWIDTH'}||1);
	my $layer=mapLayer($d{'LAYER'}) || "F.Paste";
	my $pourindex=$d{'POURINDEX'}||0;
	$pourindex-=1000 if($pourindex>=1000);
	$pourindex-=100 if($pourindex>=100);
	if(defined($pourindex) && ( $pourindex<0 || $pourindex>100))
	{
	  print STDERR "WARNING: Pourindex $pourindex out of the expected range (0 .. 100)\n";
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
	  my $minthickness='0.254000';
	  $minthickness = $thermalbridgewidth - 0.001 if ($thermalbridgewidth le $minthickness);
	  print OUT <<EOF
(zone $nettext (layer $layer) (tstamp 547BA6E6) (hatch edge 0.508) $priority
    (connect_pads thru_hole_only (clearance 0.09144))
    (min_thickness $minthickness)
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
	  print OUT "\n" if(($_ %4) == 3); # This should prevent too long lines
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
  
  $cutcounter=0;
  HandleBinFile("$short/Root Entry/Tracks6/Data.dat","\x04",0,0,\&HandleTrack);
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

  open FOUT,">$short/Root Entry/FileVersionInfo/Data.txt";
  HandleBinFile("$short/Root Entry/FileVersionInfo/Data.dat","",0,0, sub 
  { 
    my %d=%{$_[0]};
	foreach my $key (sort keys %d)
	{
	  my $v=$d{$key};
	  #print "k: $key v: $v\n";
	  $v=~s/TRUE/49/g;
	  $v=~s/FALSE/48/g;
	  my @a=split",",$v;
	  my $msg="";
	  $msg.=pack("C",$_) foreach(@a);
	  print FOUT "$key $msg\n";
	}
  });
  close FOUT;

  HandleBinFile("$short/Root Entry/Fills6/Data.dat","\x06",0,0, \&HandleFill);
  
  HandleBinFile("$short/Root Entry/Regions6/Data.dat","\x0b",0,0, sub 
  { 
    my $value=$_[1];
    $rawbinary{"Region"}{$_[3]}=$value;

    my $rt=unpack("C",substr($value,18,1));
    my @contents=();
    my @starts=();
    my @lengths=();

    my $tpos=1;
    foreach(0 .. 3)
    {
      $linebreaks{$tpos}=3;
      $starts[$_]=$tpos+2;
      $lengths[$_]=unpack("s",msubstr($value,$tpos,2,"len[$_]"));
      $lengths[$_]=16*unpack("C",msubstr($value,$tpos+2,1)."verts")+4 if($_==3);
      $contents[$_]=substr($value,$starts[$_],$lengths[$_]);
      #print "#Regions6-$_[3]-contents[$_] $lengths[$_]: ".bin2hex($contents[$_])."\n"; #  ".bin2hex(substr($value,$starts[$_]+$lengths[$_]))."\n";
      $tpos+=2+$lengths[$_];
      $tpos+=1 if($_==1);
    }
    $linebreaks{$tpos}=1;

    print OUT "#Regions#0:".escapeCRLF($_[3]).": ".bin2hexLF(substr($value,0,1000))."\n" if($annotate);
    my $unknownheader=substr($value,0,18); # I do not know yet, what the information in the header could mean

    my $POLYGON=unpack("s",substr($value,5,2)); # AUTOGENERATED
    assertdata("Region",$_[3],"POLYGON",$POLYGON) if($POLYGON>=0);
	
    my $component=unpack("s",substr($value,7,2));
    assertdata("Region",$_[3],"COMPONENT",$component) if($component>0);
	
    my $HOLECOUNT=unpack("s",substr($value,14,2)); # AUTOGENERATED, possibly other format
    assertdata("Region",$_[3],"HOLECOUNT",$HOLECOUNT);

    my $HOLE0VERTEXCOUNT=unpack("s",substr($value,14,2)); # AUTOGENERATED
    assertdata("Region",$_[3],"HOLE0VERTEXCOUNT",$HOLE0VERTEXCOUNT);

    my $textlen=unpack("l",substr($value,18,4));
	my $text=substr($value,22,$textlen);$text=~s/\x00$//;
    #assertdata("Region",$_[3],"TEXT",$text);
	print OUT "#Regions#1:$text\n" if($annotate);
	my @a=split '\|',$text;
	my %d=();
	foreach my $c(@a)
	{
	  #print "*$c*\n";
      if($c=~m/^([^=]*)=(.*)$/)
	  {
	    $d{$1}=$2;
		my $name=$1;
		my $value=$2;
		$name=~s/^V7_//;
        assertdata("Region",$_[3],$name,$value);
	  }
	}

	my $rest=substr($value,22+$textlen,length($value)-22-$textlen);
	

    my $verts=unpack("S",substr($contents[3],0,2));
    print OUT "# Verts: $verts\n";
    #print "# Verts: $verts\n";

    my $net=unpack("s",substr($value,3,2))+2;
    assertdata("Fill",$_[3],"NET",unpack("s",substr($value,3,2))) if($net>1);
    my $netname=$netnames{$net};

    my $nettext=($net>1)?"(net $net) (net_name \"$netname\")":"";

    #my $layer=mapLayer(unpack("C",substr($content,0,1))) || "Cmts.User";
    my $layer=defined($d{'V7_LAYER'})?mapLayer($d{'V7_LAYER'}):"Eco1.User";

    print OUT <<EOF
(zone $nettext (layer $layer) (tstamp 547BA6E6) (hatch edge 0.508)
    (connect_pads thru_hole_only (clearance 0.09144))
    (fill (mode segment) (arc_segments 32) )
    (polygon
      (pts
EOF
;

    foreach my $ver(0 .. $verts-1)
    {
      my $vpos=4+$ver*16;
      if($vpos>=length($contents[3]))
      {
        print "Overflow: verts:$verts ver:$ver vpos:$vpos length:".length($contents[3])." !\n";
	last;
      }

      my $x=-$xmove+mil2mm(unpack("d",msubstr($contents[3],$vpos+0,8,"X$ver")))/10000;
      my $y=+$ymove-mil2mm(unpack("d",msubstr($contents[3],$vpos+8,8,"Y$ver")))/10000;
      #print "# X$ver x/y ".bin2hex(substr($contents[3],$vpos+0,16))." $x $y \n";
      print OUT "(xy $x $y) ";
    }
	  print OUT <<EOF
      )
    )
  )
EOF
;

#	my $MAINCONTOURVERTEXCOUNT=unpack("s",substr($value,143,2)); # AUTOGENERATED, another file gives 141 as position?!?
#    assertdata("Region",$_[3],"MAINCONTOURVERTEXCOUNT",$MAINCONTOURVERTEXCOUNT);



	#my $SUBPOLYINDEX=unpack("s",substr($value,6,2)); # AUTOGENERATED
    #assertdata("Region",$_[3],"SUBPOLYINDEX",$SUBPOLYINDEX); # Seems wrong



	#print "Region: unknownheader: ".bin2hex($unknownheader)." rest: ".bin2hex($rest)."\n$text\n";
	
	
	my $datalen=unpack("l",substr($value,22+$textlen,4))*16;
	my $data=substr($value,22+$textlen+4,$datalen);
	#print bin2hex($data)."\n";
	#print "text: $text\n";
  });
  
  
  # A demo-board is created with the whole sortiment of used parts, for verification of the correct 3D models
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
    (visible_elements 7FFFF77F)
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
  print OUT "#Finished handling Shape Based Bodies.\n" if($annotate);
  
  # Converting from UCS2 to UTF-8 by removing all 0-Bytes
  sub ucs2utf($)
  {
    my $r=$_[0]; $r=~s/\x00\x00.*$//; $r=~s/\x00//gs;
	return $r;
  }
  
  my %mirrors=();
  
  if(1)
  {
    print "Texts6...\n";
	open EOUT,">$short/Root Entry/Texts6/Texts.txt";
	# It seems there are files with \r\n and files with \n but we don´t know how to distinguish those. Perhaps it depends on the Designer version?
    my $content=getCRLF(readfile("$short/Root Entry/Texts6/Data.dat"));
	my $pos=0;
	my %seen=();
	my $counter=0;
	while($pos<length($content) && $pos>=0)
	{
	  my $opos=$pos;
	  last if(substr($content,$pos,1) ne "\x05"); 
	  #print "pos: $pos\n";
	  $pos++;
      my $fontlen=unpack("l",substr($content,$pos,4)); 
	  $pos+=4;
	  
	  print EOUT bin2hex(substr($content,$pos,100))."\n";
	  #print bin2hex(substr($content,$pos,100))."\n";
	  assertdata("Text",$counter,"RECORD","Text");
	  assertdata("Text",$counter,"INDEXFORSAVE",$counter);
      $rawbinary{"Via"}{$counter}=substr($content,$pos,100);
	  my $component=unpack("s",substr($content,$pos+7,2));
	  assertdata("Text",$counter,"COMPONENT",$component) if($component>0);
	  
	  #my $texttype=unpack("C",substr($content,$pos+21,1)); # This is wrong, this is the HEIGHT field, not some type field.
	  #assertdata("Text",$counter,"TYPE",$texttype);
	  
	  my $comment=unpack("C",substr($content,$pos+40,1));
	  assertdata("Text",$counter,"COMMENT",$alttruth{$comment}) if($comment);
	  my $designator=unpack("C",substr($content,$pos+41,1));
	  assertdata("Text",$counter,"DESIGNATOR",$alttruth{$designator}) if($designator);

	  my $hide=0;
	  if($component>=0)
	  {
	    if($comment) #$texttype == 0xc0)
		{
		  #assertdata("Text",$counter,"COMMENT","TRUE");
		  $hide=1 if($commenton{$component} eq "FALSE");
		}
		elsif($designator) # $texttype == 0xf2)
		{
		  #assertdata("Text",$counter,"DESIGNATOR","TRUE");
		  $hide=1 if($nameon{$component} eq "FALSE");
		}
		else
		{
		  $hide=1;
		}
	  }
	  
	  my $layer=mapLayer(unpack("C",substr($content,$pos,1))) || "Cmts.User";
	  my $olayer=unpack("C",substr($content,$pos,1));
  	  assertdata("Text",$counter,"LAYER",$altlayername{$olayer}) if(defined($altlayername{$olayer}));
	  print STDERR "Undefined Text layer $olayer\n" if(!$altlayername{$olayer});
	  
	  my $x=sprintf("%.5f",-$xmove+bmil2mm(substr($content,$pos+13,4)));
	  assertdata("Text",$counter,"X",bmil2(substr($content,$pos+13,4)));
	  my $y=sprintf("%.5f",+$ymove-bmil2mm(substr($content,$pos+17,4)));
      assertdata("Text",$counter,"Y",bmil2(substr($content,$pos+17,4)));

	  #my $x1=sprintf("%.5f",-$xmove+bmil2mm(substr($content,$pos+13,4)));
	  #assertdata("Text",$counter,"X1",bmil2(substr($content,$pos+13,4)));
	  #my $y1=sprintf("%.5f",+$ymove-bmil2mm(substr($content,$pos+17,4)));
      #assertdata("Text",$counter,"Y1",bmil2(substr($content,$pos+17,4)));
	  #my $x2=sprintf("%.5f",-$xmove+bmil2mm(substr($content,$pos+13,4)));
	  #assertdata("Text",$counter,"X2",bmil2(substr($content,$pos+13,4)));
	  #my $y2=sprintf("%.5f",+$ymove-bmil2mm(substr($content,$pos+17,4)));
      #assertdata("Text",$counter,"Y2",bmil2(substr($content,$pos+17,4)));
	  
	  my $width=bmil2mm(substr($content,$pos+21,4));
      assertdata("Text",$counter,"HEIGHT",bmil2(substr($content,$pos+21,4)));
	  my $dir=unpack("d",substr($content,$pos+27,8)); 
      assertdata("Text",$counter,"ROTATION",enull(sprintf("%.14E",unpack("d",substr($content,$pos+27,8)))));
	  my $mirror=unpack("C",substr($content,$pos+27+8,1));
	  assertdata("Text",$counter,"MIRROR",uc($alttruth{$mirror}));
	  my $font=substr($content,$pos,$fontlen); 
	  $pos+=$fontlen;
	  my $fontname=ucs2utf(substr($font,46,64));
	  assertdata("Text",$counter,"FONTNAME",$fontname);
      my $textlen=unpack("l",substr($content,$pos,4)); 
	  $pos+=4;
	  my $text=substr($content,$pos+1,$textlen-1); 
  	  assertdata("Text",$counter,"TEXT",$text);
	  $pos+=$textlen;
	  print OUT "#Texts#".$opos.": ".bin2hexLF(substr($content,$opos,$pos-$opos))."\n" if($annotate);
	  print OUT "#Layer: $olayer Component:$component COMMENT=$comment DESIGNATOR=$designator\n" if($annotate);
	  print OUT "#Commenton: ".($commenton{$component}||"")." nameon: ".($nameon{$component}||"")."\n" if($component>=0 && $annotate);
	  print OUT "#Mirror: $mirror\n" if($annotate);
	  $mirrors{$mirror}++;
	  my $mirrortext=$mirror?" (justify mirror)":"";
	  print OUT "#hide: $hide (".escapeCRLF($text).")\n" if($annotate);
	  $text=~s/"/''/g;
	  $text=escapeCRLF($text);
	  print OUT <<EOF
 (gr_text "$text" (at $x $y $dir) (layer $layer)
    (effects (font (size $width $width) (thickness 0.1)) (justify left)$mirrortext)
  )
EOF
        if(!$hide);
	  $counter++;
	}
    close EOUT;	
  } 

  # We are done with converting a .PcbDoc file, now we print some statistical information: 
  if(keys %unmappedLayers)
  {
    print "Unmapped Layers:\n";
    print join ",",map { "\"$_\"=>\"$unmappedLayers{$_}\""} keys %unmappedLayers;
    print "\n";
  }
  
  # We can print the used layers
  foreach(sort keys %usedlayers)
  {
    my $name="undefined"; $name=$1 if($layerdoku=~m/name: *$_ *([\w.]+)/);
	my $kic=$layermap{$_} || "undefined";
	my $lname=$layername{$_} || "undefined";
    #print "Used layer: $_ $lname/$name -> $kic\n";
  }
  
  sub findall($$)
  {
    my @ret=();
	return @ret if(!defined($_[0]) || !defined($_[1]));
    my $result = index($_[0], $_[1], 0);
    while ($result != -1) 
    {
      push @ret,$result;
      $result = index($_[0], $_[1], $result+1);
	}
	return @ret;
  }

  # Verification of binary parsing against the ascii fileformat:
  if(scalar(@asciilines))
  {
    print "Writing report to $short-ascii.html\n";
    open HTML,">$short-ascii.html";
	print HTML "<html><body><pre>";
	my %linenos=();
	my %tosearch=();
  	foreach my $line (@asciilines)
	{
      my @a=split '\|',$line;
	  my %d=();
	  my $lineno=0;
	  foreach my $c(@a)
	  {
  	    #print "$c\n";
        if($c=~m/^([^=]*)=(.*)$/)
	    {
  	      my $name=$1;
		  my $value=$2; $value=~s/[\r\n]$//;
		  $d{$name}=$value;
		  $lineno=$linenos{$value}++ if($name eq "RECORD");
		  my $resultvalue=$result{$d{'RECORD'}}{$lineno}{$name};
	      my $good=(defined($resultvalue) && $resultvalue eq $value) ? 1:0;
		  
		  print HTML "<span style='background-color:".(defined($resultvalue)?($good?"#80ff80":"#ff8080"):"#ffffff")."'>".$name."=".$value."</span>";
		  print HTML "<span style='background-color:#8080ff'>$resultvalue</span>" if(defined($resultvalue) && !$good);
		  print HTML "|";
		  
		  if(length($rawbinary{$d{'RECORD'}}) && defined($result{$d{'RECORD'}} )) #&& !$good
		  {
			my $tosearch=EstimateEncoding($value);
			if(length($tosearch))
			{
			  #print "record=".$d{'RECORD'}." - lineno: $lineno\n";
			  my $plain=$rawbinary{$d{'RECORD'}}{$lineno};
			  #print "Searching ".bin2hex($tosearch)." in ".bin2hex($plain)."\n";
			  my @l=findall($plain,$tosearch);
              $positions{$d{'RECORD'}}{$name}{$_}++ foreach(@l);
			}
	      }
	    }
	  }
	  print HTML "\n";
	}
	print HTML "</pre>";
	
	print "Guessing binary fields...\n";
    foreach my $rec(sort keys %positions)
	{
	  foreach my $name(sort keys %{$positions{$rec}})
	  {
        print "RECORD=$rec name=$name\n";
		my $max=undef;
		my $rightpos=undef;
		my $count=0;
		foreach my $pos(sort {$positions{$rec}{$name}{$b} <=> $positions{$rec}{$name}{$a}} keys %{$positions{$rec}{$name}})
        {
		  my $v=$positions{$rec}{$name}{$pos};
		  if(!defined($max))
		  {
		    $max=$v; $rightpos=$pos;
		  }
		  $count++ if($max==$v);
		  print "  $pos $v\n" if($max==$v);
		}
		if($count==1)
		{
          print "RECORD=$rec name=$name max:$max rightpos:$rightpos count:$count\n";
		  my $len=1;
		  print "  my \$$name=substr(\$content,$rightpos,$len)\n";
		}
	  }
	}
	
	print HTML "</body></html>";
	close HTML;   	
  }
  
  print OUT ")\n";
}


sub rem0($)
{
  my $d=$_[0]; $d=~s/\x00//g;
  return $d;
}

# The following function decodes an old Designer version 9? .lib file
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
  while($pos<length($content) && $pos>=0)
  {
    #print "pos: ".sprintf("%02X",$pos)." ";
    my $recordtype=unpack("C",substr($content,$pos,1));
    if($recordtype==4)
	{
	  if(substr($content,$pos+4,1)ne"\x7C")
	  {
	    my $len=unpack("S",substr($content,$pos+12,2));
	    #print "Record 4a with len $len found: ".bin2hex(substr($content,$pos+1,11))."   ".rem0(substr($content,$pos+14,$len))."\n";
	    $pos+=12+2+$len;
      }
	  else
	  {
        my $len=unpack("S",substr($content,$pos+2,2));
        #print "Record 4b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	}
    elsif($recordtype==5)
	{
	  if(unpack("C",substr($content,$pos+1,1))==0)
	  {
  	    my $len=unpack("S",substr($content,$pos+2,2));
	    #print "Record 5b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	  else
	  {
	    my $len=2*unpack("S",substr($content,$pos+8,2));
	    #print "Record 5a with len $len found ".bin2hex(substr($content,$pos+1,7))." ".bin2hex(substr($content,$pos+8,2))." ".rem0(substr($content,$pos+10,$len))."\n";
	    $pos+=8+2+$len;
      }
	}
    elsif($recordtype==2)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  #print "Record $recordtype with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
    elsif($recordtype==3)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  #print "Record $recordtype with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
    elsif($recordtype==1)
	{
	  my $len=unpack("S",substr($content,$pos+2,2));
	  #print "Record 1 with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	  $pos+=2+2+$len;
	}
	elsif($recordtype==6)
	{
      if(unpack("C",substr($content,$pos+1,1))==0)
	  {
  	    my $len=unpack("S",substr($content,$pos+2,2));
	    #print "Record 6b with len $len found: ".rem0(substr($content,$pos+4,$len))."\n";
	    $pos+=2+2+$len;
	  }
	  else
	  {
        #print "Record 6a with len 266 found ".(substr($content,$pos+1,$recordtype))."\n";
	    $pos+=266;
	  }	
	}
	elsif($recordtype>=7 && $recordtype<=40)
	{
	  #print "Record $recordtype with len 256 found: ".substr($content,$pos+1,$recordtype)."\n";
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
  while($pos<length($content) && $pos>=0)
  {
    my $typelen=unpack("S",substr($content,$pos,2));
    my $type=substr($content,$pos+4,$typelen);
	if(substr($type,0,1)eq "|")
	{
      #print "pos: $pos typelen: $typelen type: $type\n";
	}
	else
	{
      #print "pos: $pos typelen: $typelen type: ".bin2hex(substr($content,$pos+2,$typelen+2))."\n";	
	}
    $pos+=$typelen+4;
  }
}

foreach(glob("'library/Miscellaneous Devices/Root Entry/SchLib/0/Root Entry/*/Data.dat'"))
{
 # decodeSchLib($_);
}

# This function decodes a new .PcbLib file
sub decodePcbLib($)
{
  our $componentid=0;
  our %componentatx=();
  our %componentaty=();
  our %componentlayer=();
  our %componentrotate=();
  our %kicadwrl=();
  our %componenthandled=();
  our %kicadwrlerror=();
  our %netnames=();
  our %pads=();
  my $counter=0;
  my $content=readfile($_[0]);
  
  my @dirs=split "/",$_[0];
  my $short=$dirs[0]; $short=~s/-PcbLib$//;
  my $module=$dirs[-2];
  print "Full: $_[0] Short: $short Module: $module\n";
  #exit;
  mkdir "$short.pretty";
  print "Writing to $short.pretty/$module.kicad_mod\n";
  open OUT,">$short.pretty/$module.kicad_mod";
  
  print OUT "(module \"$module\" (layer F.Cu) (tedit 5B0D3C36)\n";

  next unless defined($content);
  print "Decoding $_[0] (".length($content)." Bytes)...\n";
  
  my $namelen=unpack("S",substr($content,0,2));
  print "Name: ".substr($content,5,$namelen-1)."\n";
    
  my $pos=4+$namelen;
  my $prevtype=-1;
  
  HandlePads(substr($content,$pos),$_[0]);
  
  print OUT ")\n";
  close OUT;
	
}

foreach(glob("'library/Miscellaneous Devices/Root Entry/PcbLib/0/Root Entry/*/Data.dat.bin'"))
{
  #decodePcbLib($_);
}
foreach my $dir (glob("'*/Root Entry/Library'"))
{
  $dir=~s/\/Library$//;
  foreach(glob("'".$dir."/*/Data.dat.bin'"))
  {
    next if(m/\/Library\/Data.dat.bin/);
    next if(m/\/FileVersionInfo\/Data.dat.bin/);
    decodePcbLib($_); ### Causes problems, needs more testing first
    #print "Done decoding PCBLIB $_\n";
  }
}

# Calculating statistics for ASCII*.PcbDoc files into ASCII*.PcbDoc.txt files
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

if(!$filecounter)
{
  print "There were no unpacked PcbDoc files found.\n";
}
