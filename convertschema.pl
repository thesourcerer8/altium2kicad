#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin";
use Math::Bezier;
use POSIX qw(strftime);
use File::Glob qw(:globally :nocase);

my $searchimagemagick="\\Program Files\\ImageMagick-6.8.9-Q16\\";

my $imagemagick=-d $searchimagemagick?$searchimagemagick:"";

# Things that are missing in KiCad (BZR5054):
# Y2038 support: The "unique" timestamps are only 32 Bit epoch values, any larger numbers are cut off without any error or warning. At the moment those timestamps are only used for uniqueness, but they might be used for more versioning/historisation in the future.
# The unique timestamps only have a 1 second accuracy. If several people are working together on a hierarchical project, they might create 2 different objects in the same second. Fast Generators and Converters or Plugins might also create many objects in the same second.
# Bezier curves for component symbols -> WONTFIX -> Workaround
# Multi-line Text Frames
# A GND symbol with multiple horizontal lines arranged as a triangle
# Individual colors for single objects like lines, ...
# Ellipse -> Workaround: They have to be approximated
# Round Rectangle -> Workaround: They have to be approximated
# Elliptical Arc -> Workaround: They have to be approximated
# Printing does not work correctly
# Exporting to PDF only creates a single page, does not work for hierarchical schematics yet
# Arcs with >=180 degrees angle. Workaround: Such arcs are splitted into 3 parts
# Dotted and dashed lines

# Things that are missing in Altium:
# Altium does not differentiate between "Power-In" and "Power-Out", it only has "Power"
# -> therefore the Input-Ouput connectivity between Power-In and Power-Out cannot be checked by the KiCad Design-Rules-Check
# Possible workaround: Map Altium-Power to KiCad-Power-In or KiCad-Power-Out and disable the checks in KiCad by allowing Power-In <-> Power-In connections
# When necessary work through all Power Pins and correct the In-Out setting afterwards

# Things that are missing in this converter:
# Automatic layer assignment, at the moment this converter is specialized for Novena, it might not work correctly for other projects with different layer definitions
# Worksheet definitions

# Documentation for the Altium Schematic Fileformat can be found at 
# https://github.com/vadmium/python-altium/blob/master/format.md

# Security considerations
# This tool is currently not designed to be executed on malicious data, so do not run a public webservice with it
# The core parsing code should be safe, the biggest risk is likely the invocation of ImageMagick for image conversion


my $pi=3.14159265359;

my $USELOGGING=1;
my $globalcomp="";
our %globalcontains=();
my %rootlibraries=();
my $ICcount=0;
my $start_time=$ENV{'A2K_STARTTIME'} || time();
our $timestamp=$start_time;  # this value gets decreased every time we need a unique timestamp
my %hvmap=("0"=>"H","1"=>"V","2"=>"H","3"=>"V");
our %uniquereferences=();
my %myrot=("0"=>"0","90"=>"1","270"=>"2");
my %iotypes=("0"=>"BiDi","1"=>"Output","2"=>"Input","3"=>"BiDi"); # Others unknown yet (0 is really 'unspecified' in Altium)
my %partparams=();

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

sub uniqueid2timestamp($)
{
  my $v=$timestamp--;
  return sprintf("%08X",$v);
  # Old code that converts UniqueIDs to Timestamps, unfortunately we don´t have the UniqueIDs where we need Timestamps :-(
  my $ret="";
  my $A=unpack("C","A");
  foreach(split "",$_[0])
  {
    $ret.=sprintf("%01X",(10+unpack("C",$_)-$A)%16);
  }
  return $ret;
}

sub uniquify($)
{
  my $ref=$_[0];
  if(defined($uniquereferences{$ref}))
  {
    for(2 .. 1000)
	{
  	  if(!defined($uniquereferences{$_[0]."_$_"}))
	  {
	    $ref=$_[0]."_$_";
	    last;
	  }
    }
  }
  $uniquereferences{$ref}=1;
  return $ref;
}

sub get_f_position(\%$$$$$) {
    my ($dref, $f, $part_orient, $relx, $rely, $sheety) = @_;
    my %d = %$dref;

    #my $x=($d{'LOCATION.X'}*$f);
    #my $y=($d{'LOCATION.Y'}*$f);
    my $x=((($d{'LOCATION.X'}||0)+(($d{'LOCATION.X_FRAC'}||0)/100000.0))*$f);
    my $y=((($d{'LOCATION.Y'}||0)+(($d{'LOCATION.Y_FRAC'}||0)/100000.0))*$f);

    my $orientation=$d{'ORIENTATION'} || 0;
    $orientation=($orientation + $part_orient) % 4;

    #print "d{ORIENTATION}: ".($d{ORIENTATION}||"")." orientation: $orientation\n";
    #print "LOC.X: ".($d{'LOCATION.X'}*$f)." relx: $relx\n";
    #print "LOC.Y: ".($d{'LOCATION.Y'}*$f)." rely: $rely sheety=$sheety\n";
    my $ownrot=(($part_orient || 0) % 4) + ($d{'ISMIRRORED'}?4:0);
    my $ownrot2=(($part_orient || 0)) % 4; #$orientation+
    $ownrot2=($d{'ORIENTATION'})%4 if($d{'ORIENTATION'}); # This line is most likely buggy and should be improved
    #ext if($ownrot!=$ownrot2);
    #next unless($d{'ORIENTATION'});
    #next if($ownrot!=1);

    #print $d{'TEXT'}." -> $t -> $commentpos{$LIBREFERENCE}\n"; # if($d{'NAME'} eq "Rule");
    #print "906: $d{TEXT} globalp:$globalp orient:$orientation partorient:".($partorientation{$globalp}||"")." ownrot:$ownrot ownrot2:$ownrot2\n"; # if(!defined($ownrot));

    ($x,$y)=rotatepivot($x,$y,$ownrot,$relx,$rely);
    #print "resultx: $x\nresulty: $y\n";
    $y=$sheety-$y;

    $x = int($x);
    $y = int($y);

    my $orient = $hvmap{$orientation};
    my $dir = mapDir($ownrot2,$d{'ISMIRRORED'},0);
    return ($x, $y, $orient, $dir);
}

#Protel for Windows - Schematic Capture Ascii File Version 5.0    -> supported
#DProtel for Windows - Schematic Capture Binary File Version 1.2 - 2.0    -> not supported

foreach my $filename(glob('"*/Root Entry/FileHeader.dat"'), glob('"*.sch"'), glob('"*.schdoc"'))
{
  print "Handling $filename\n";
  my $short=$filename; 
  my $protel=($filename=~m/Root Entry\/FileHeader\.dat/)?0:1;
  $short=~s/\/Root Entry\/FileHeader\.dat$//;
  $short=~s/\.sch$/-kicad/i;
  next if -d "$short/Root Entry/Arcs6"; # Skipping PCB files
  open IN,"<$filename";
  undef $/;
  my $content=<IN>;
  close IN;
  
  next unless defined($content);
  next unless length($content)>4;
  next if($content=~m/EESchema Schematic File Version/); # Skipping KiCad schematics
  next if($content=~m/PCB \d+.\d+ Binary Library File/); # Skipping PCB Files
  next if(substr($content,0,2) eq "\xD0\xCF");
  next if((!$protel) && unpack("l",substr($content,0,4))>length($content));

  my $text="";
  my @a=();
  
  our %localcontains=();
  our %partstextcounter=();

  open OUT,">$filename.txt";
  my $line=0;
  
  if($content=~m/Protel for Windows - Schematic Capture Ascii File/)
  {
    foreach(split "\n",$content)
    {
      s/\r//;
      push @a,"|LINENO=$line|$_";
      print OUT "$_\n\n";
      $line++;
    }
  }
  else
  {
    while(length($content)>4 )
    {
      my $len=unpack("l",substr($content,0,4));
	  if($len<0)
	  {
        print "Error: Length is negative $filename $line: $len\n";
	    last;
	  }
    
      #print "len: $len\n";
      my $data=substr($content,4,$len); 
      if($data=~m/\n/)
      {
        #print "Warning: data contains newline!\n";
      }
      $data=~s/\x00//g;
      push @a,"|LINENO=$line|".$data;
      $text.=$data."\n";
      print OUT $data."\n";
      substr($content,0,4+$len)="";  
	  $line++;
    }
  }
  close OUT;


  open LOG,">$short.log" if($USELOGGING);
  open LIB,">$short-cache.lib";
  binmode(LIB, ":utf8");
  my $timestamp=strftime("%d.%m.%Y %H:%M:%S", localtime($start_time));
  print LIB "EESchema-LIBRARY Version 2.3  Date: $timestamp\n#encoding utf-8\n";

  open OUT,">$short.sch";
  binmode(OUT, ":utf8");
  print OUT "EESchema Schematic File Version 4\n";
  
  my %formats=(0=>"A4 11693 8268",1=>"A3 16535 11693",2=>"A2 23386 16535",3=>"A1 33110 23386",4=>"A0 46811 33110",5=>"A 11000 8500", 6=>"B 17000 11000",7=>"C 22000 17000",8=>"D 34000 22000",9=>"E 44000 34000",10=>"USLetter 11000 8500",11=>"USLegal 14000 8500",12=>"USLedger 17000 11000",13=>"A 11000 8500",14=>"B 17000 11000",15=>"C 22000 17000",16=>"D 34000 22000",17=>"E 44000 34000");
  
  my $sheetstyle=6; $sheetstyle=$1 if($text=~m/SHEETSTYLE=(\d+)/);
  
  my $sheetformat=$formats{$sheetstyle};
  if(!defined($sheetformat))
  {
    print "Not found: sheetstyle=$sheetstyle\n";
  }
  if($text=~m/WORKSPACEORIENTATION=1/)
  {
    $sheetformat="$1 $3 $2 portrait" if($sheetformat=~m/(\w+) (\d+) (\d+)/);
  }
  
  my $sheety=12000; $sheety=$1 if($sheetformat=~m/\w+ \d+ (\d+)/);

  my $datetext=strftime("%d %m %Y", localtime($start_time));

  print OUT <<EOF
EELAYER 30 0
EELAYER END
\$Descr $sheetformat
encoding utf-8
Sheet 1 1
Title "$short"
Date "$datetext"
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
\$EndDescr
EOF
;

  my %parts=();
  my $prevfilename="";
  my $prevname="";
  my $symbol="";
  my %globalf=();
  my $globalp=0;
  my %globalcomment=();
  my %globalreference=();
  my %componentheader=();
  my %designatorpos=();
  my %commentpos=();
  my %xypos=();
  my %lib=();
  our %componentdraw=();
  our %customfields=();
  our %componentcontains=();
  our $LIBREFERENCE;
  my %partcomp=();
  my $relx=0;
  my $rely=0;
  my $relh=0;
  my $relw=0;
  my $nextxypos=undef;
  my $CURRENTPARTID=undef;
  my %partorientation;
  my $OWNERPARTDISPLAYMODE=undef;
  my $OWNERLINENO=0;
  
  my %fontsize=();
  my %fontbold=();
  my %fontkursiv=();
  my %fontrotation=();
  
  my %winkel=("0"=>0,"1"=>90,"2"=>180,"3"=>270);

  # Rotates 2 coordinates x y around the angle o and returns the new x and y
  sub rotate($$$) # x,y,o
  {
    my $o=$_[2]||0; 
	my $m=($_[2]||0)&4;
	$o&=3; # Perhaps mirroring needs something else?
	#orient=("0"=>"1    0    0    -1","1"=>"0    1    1    0","2"=>"-1   0    0    1","3"=>"0    -1   -1   0");
	if(!$o)
	{
	   return($m?-$_[0]:$_[0],$_[1]);
	}
	elsif($o eq "1")
	{
	   return($m?-$_[1]:$_[1],-$_[0]);
	}
	elsif($o eq "2")
	{
	   return($m?$_[0]:-$_[0],-$_[1]);
	}
	elsif($o eq "3")
	{
	   #print "Drehe 3\n";
	   return($m?$_[1]:-$_[1],$_[0]);
	}
  }

  sub rotatepivot($$$$$) # x,y,o,px,py
  {
    my $x=$_[0]-$_[3];
	my $y=$_[1]-$_[4];
	$y=-$y;
    my $o=$_[2]; 
	my $m=$_[2]&4;
	$o&=3;
	if(!$o)
	{
	   return(($m?-$x:$x)+$_[3],$y+$_[4]);
	}
	elsif($o eq "1")
	{
	   return(($m?$y:-$y)+$_[3],$x+$_[4]);
	}
	elsif($o eq "2")
	{
	   return(($m?$x:-$x)+$_[3],-$y+$_[4]);
	}
	elsif($o eq "3")
	{
	   return(($m?-$y:$y)+$_[3],-$x+$_[4]);
	}
  }

  
  sub mapDir($$$)
  {
    my $mirrored=defined($_[1])?$_[1]:0;
	my $debug=$_[2];
    my %dirmap=("0"=>"L BNN","1"=>"R TNN","2"=>"R TNN","3"=>"L BNN");
    my %dirmapmirrored=("0"=>"R BNN","1"=>"L TNN","2"=>"L TNN","3"=>"R BNN");
	#print "Mapping $_[0] (Mirror: $mirrored) to: ".($mirrored? $dirmapmirrored{$_[0]}:$dirmap{$_[0]})."\n" if($debug);
	return $mirrored?$dirmapmirrored{$_[0]}:$dirmap{$_[0]};
  }
  
  my %globalparams=();
  
  # Preprocess to find references for xrefs - yugh
  foreach my $b(@a)
  {
    #print "b: $b\n";
    my %d=();
    my @l=split('\|',$b);
    foreach my $c(@l)
    {
      #print "c: $c\n";
      if($c=~m/^([^=]*)=(.*)$/s)
      {
        #print "$1 -> $2\n";
        $d{uc $1}=$2;
      }
    }
    next unless defined($d{'RECORD'});
    if ( $d{'RECORD'} eq '41' )
    {
      if (defined($d{'NAME'}) && !defined($d{'COMPONENTINDEX'}))
      {
        $globalparams{lc($d{'NAME'})} = $d{'TEXT'};
      }
    }
  }
  
  foreach my $b(@a)
  {
    #print "b: $b\n";
    my %d=();
    my @l=split('\|',$b);
    foreach my $c(@l)
    {
      #print "c: $c\n";
      if($c=~m/^([^=]*)=(.*)$/s)
      {
        #print "$1 -> $2\n";
        $d{uc $1}=$2;
      }
    }
    # Now we have parsed key value pairs into %d
	
	my $o="";
	my %ignore=("RECORD"=>1,"OWNERPARTID"=>1,"OWNERINDEX"=>1,"INDEXINSHEET"=>1,"COLOR"=>1,"READONLYSTATE"=>1,"ISNOTACCESIBLE"=>1,"LINENO"=>1);
	foreach(sort keys %d)
	{
	  next if defined($ignore{$_});
	  $o.="$_=$d{$_}|";$o=~s/\r\n//s;
	}
	
	print LOG sprintf("RECORD=%2d|LINENO=%4d|OWNERPARTID=%4d|OWNERINDEX=%4d|%s\n",defined($d{'RECORD'})?$d{'RECORD'}:-42,$d{'LINENO'},defined($d{'OWNERPARTID'})?$d{'OWNERPARTID'}+1:-42,defined($d{'OWNERINDEX'})?$d{'OWNERINDEX'}+1:-42,$o) if($USELOGGING);

	
    next unless defined($d{'RECORD'});
    my $f=10;
 
	
	my $dat="";
	
	sub drawcomponent($)
	{
  	  $componentdraw{$LIBREFERENCE||0}.=$_[0] unless(defined($componentcontains{$LIBREFERENCE||0}{$_[0]}));
      $componentcontains{$LIBREFERENCE||0}{$_[0]}=1;
	}
	
	if ($d{'RECORD'} ne '34') {
	  # ignore hidden records, except type 34 (designator)
	  #next if(defined($d{'ISHIDDEN'}) && $d{'ISHIDDEN'} eq "T");
	}

	if(defined($OWNERPARTDISPLAYMODE) && defined($d{'OWNERINDEX'}))
	{
	  #print "Checking for\nOWNERINDEX: $d{'OWNERINDEX'} vs. ".($OWNERLINENO-1)." ?\n $OWNERPARTDISPLAYMODE vs. ".($d{'OWNERPARTDISPLAYMODE'}||-1)." ?\n";
	  next if ((($d{'OWNERINDEX'} || 0) eq $OWNERLINENO-1) && ($d{'OWNERPARTDISPLAYMODE'}||-1) ne $OWNERPARTDISPLAYMODE); 
	}
	
	if(($d{'OWNERPARTID'}||"") eq "0")
	{
	  print "Warning: Edge case: OWNERPARTID=".(defined($d{'OWNERPARTID'})?$d{'OWNERPARTID'}:"")." RECORD=$d{'RECORD'} the behaviour has been changed on 2018-01-05. If this causes a regression, please file an issue.\n";
	}
	
    if(defined($d{'OWNERPARTID'}) && $d{'OWNERPARTID'}>0)
	{
	  if(defined($CURRENTPARTID))
	  {
        next if($CURRENTPARTID ne $d{'OWNERPARTID'});
	  }

	  if($d{'RECORD'} eq '4') # Label
	  {
	    #|RECORD=4|LOCATION.X=40|TEXT=I2C mappings:|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|LOCATION.Y=500|FONTID=3
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
        my $fid=4+$globalf{$globalp}++;
        my $o=($d{'ORIENTATION'}||0)*900;
		my $size=$fontsize{$d{'FONTID'}}*6;
        my $value=$d{'TEXT'};
        if ( substr($value,0,1) eq '=' ) # It's an xref - look it up
        {
            my $paramname = substr($value,1);
            $value = $globalparams{lc($paramname)} || $value;
        }
	    drawcomponent "T $o $x $y $size 0 1 1 \"$value\" Normal 0 L B\n";
	  }
	  elsif($d{'RECORD'} eq '32') # Sheet Name
	  {
	    #|RECORD=32|LOCATION.X=40|TEXT=U_02cpu_power|OWNERINDEX=42|OWNERPARTID=-1|COLOR=8388608|INDEXINSHEET=-1|LOCATION.Y=240|FONTID=1
		my $f=$globalf{$globalp}++;
		my $TEXT=$d{'TEXT'}; $TEXT=~s/"/'/g;
	    $dat.="F $f \"$TEXT\" H ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)."\n";		
	  }
	  elsif($d{'RECORD'} eq '13') # Line
	  {
	    #|RECORD=13|ISNOTACCESIBLE=T|LINEWIDTH=1|LOCATION.X=581|CORNER.Y=1103|OWNERPARTID=1|OWNERINDEX=168|CORNER.X=599|COLOR=16711680|LOCATION.Y=1103
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		drawcomponent "P 2 0 1 10 $x $y $cx $cy\n";
	  }
	  elsif($d{'RECORD'} eq '14') # Rectangle
	  {
	    #RECORD=14|OWNERPARTID=   8|OWNERINDEX=  27|AREACOLOR=11599871|CORNER.X=310|CORNER.Y=1370|ISSOLID=T|LINEWIDTH=2|LOCATION.X=140|LOCATION.Y=920|OWNERINDEX=27|TRANSPARENT=T|
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		drawcomponent "S $x $y $cx $cy 0 1 10 f\n";
	  }
 	  elsif($d{'RECORD'} eq '28') # Text Frame
	  {
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
        ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		my $text=$d{'TEXT'}; $text=~s/\~1/\~/g; $text=~s/ /\~/g;
		if($text=~m/\n/)
		{
		  print "Line-breaks not implemented yet!\n";
		}
		drawcomponent "T 0 $x $y 100 0 1 1 $text 1\n";
      }	  
	  elsif($d{'RECORD'} eq '2') # Pin
	  {
	    my $oldname=$d{'NAME'} || "P";
		$oldname=~s/ //g;
		our $state=0;
		my $name="";
		foreach(split("",$oldname))
		{
          if($state==0)
          {
		    if($_ eq "\\")
			{
			  $state=1;
			}
			elsif($_ eq " ")
			{}
			else
			{
			  $name.=$_;
			}
          }
		  elsif($state==1)
		  {
		    if($_ eq "\\")
			{
			  $name.=$_;
			}
			else
			{
			  $name.="~".$_;
			  $state=2;
			}
		  }
		  elsif($state==2)
		  {
		    if($_ eq "\\")
			{
			  $state=3;
			}
			else
			{
			  $name.="~".$_;
			  $state=0;
			}
		  }
		  elsif($state==3)
		  {
		    if($_ eq "\\")
			{
			  $name.="".$_;
			  $state=2;
			}
			else
			{
			  $name.="".$_;
			  $state=2;
			}
		  }
		}
		my $brokenname=$name;
		$name="";
		my $namepos=0;
		$state=0;
		while($namepos < length($oldname) && $namepos>=0)
		{
		  my $thisstate=(defined(substr($oldname,$namepos+1,1)) && substr($oldname,$namepos+1,1) eq "\\")?1:0;
		  if($thisstate != $state)
		  {
		    $name.="~";
		  }
		  $state=$thisstate;
		  $name.=substr($oldname,$namepos,1) unless(substr($oldname,$namepos,1)eq "\\" && !$thisstate);
		  $namepos+=$thisstate?2:1;
		}
		#print "oldname: $oldname brokenname:$brokenname name:$name\n" if($brokenname ne $name);
		if(defined($d{'LOCATION.X'})&&defined($d{'LOCATION.Y'}))
		{
		  my %dirtext=("0"=>"L","1"=>"D","2"=>"R","3"=>"U");
		  my $pinorient=($d{'PINCONGLOMERATE'}||0)&3;
		  my $pinnamesize=(($d{'PINCONGLOMERATE'}||0)&8)?70:1; # There is a bug in KiCad´s plotting code BZR5054, which breaks all components when this size is 0
		  my $pinnumbersize=(($d{'PINCONGLOMERATE'}||0)&16)?70:1; # The :1 should be changed to :0 as soon as the bug is resolved.
		  my %map2=("0"=>"0","1"=>"3","2"=>"2","3"=>"1");
		  $pinorient+=$map2{($partorientation{$globalp}||0)&3}; $pinorient&=3;
		  my $mirrored=($partorientation{$globalp}||0)&4;
		  my $dir=$dirtext{$pinorient};
		  my $x=$d{'LOCATION.X'}*$f;
		  my $y=$d{'LOCATION.Y'}*$f;
		  my $pinlength=($d{'PINLENGTH'}||1)*$f;
		  my $electrical="U";
		  
		  $x-=$relx;
		  $y-=$rely;
          ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  
		  my %mirrors=("R"=>"L","L"=>"R","D"=>"D","U"=>"U");
		  $dir=$mirrors{$dir} if($mirrored);

		  $x-=$pinlength if($dir eq "R");
		  $x+=$pinlength if($dir eq "L");
		  $y+=$pinlength if($dir eq "D");
		  $y-=$pinlength if($dir eq "U");
		  my $E="I"; my %electricmap=("0"=>"I","1"=>"B","2"=>"O","3"=>"C","4"=>"P","5"=>"T","6"=>"E","7"=>"W"); 
		  $E=$electricmap{$d{'ELECTRICAL'}} || "I" if(defined($d{'ELECTRICAL'}));
		  my $F=""; # $F=" F" if($d{'ELECTRICAL'}eq "7"); Unfortunately, Altium and KiCad have different meanings for the same symbols
		  #$pinnumbersize=60; $pinnamesize=60;  # Plotting hangs when the sizes are 0, this should be changed 
		  # $name must not be empty for KiCad!
		  drawcomponent "X $name $d{DESIGNATOR} $x $y $pinlength $dir $pinnumbersize $pinnamesize 0 1 $E$F\n";
	    }
		else
		{
		  print "$d{'RECORD'} $name without Location!\n";
		}
	  
	  }
	
      elsif($d{'RECORD'} eq '3') # Pin symbol
	  {
        #|RECORD=3|OWNERINDEX=1989|ISNOTACCESIBLE=T|INDEXINSHEET=9|OWNERPARTID=1|SYMBOL=1|LOCATION.X=1145|LOCATION.Y=821|SCALEFACTOR=10
        my $x=($d{'LOCATION.X'}*$f)-$relx;
        my $y=($d{'LOCATION.Y'}*$f)-$rely;
        ($x,$y)=rotate($x,$y,$partorientation{$globalp});
        if ( $d{'SYMBOL'} eq '1' )
        {
            # A 'Not' symbol - a small circle
            drawcomponent "C $x $y ".(($d{'SCALEFACTOR'}||10)*$f/5.0)." 0 1 10 N\n";
        }
        else
        {
            print "WARNING: Pin symbol type $d{'SYMBOL'} not understood - IGNORING!\n";
        }
      }
      elsif($d{'RECORD'} eq '6'|| $d{'RECORD'} eq '5') # Polyline or Bezier!
	  {
        #RECORD=5|OWNERINDEX=183|ISNOTACCESIBLE=T|INDEXINSHEET=12|OWNERPARTID=1|LINEWIDTH=1|COLOR=16711680|LOCATIONCOUNT=2|X1=464|Y1=943|X2=466|Y2=946
        #RECORD= 6|OWNERPARTID=   1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
        print "WARNING: Bezier paths are not supported in KiCad - creating a basic polyline through the control points instead\n" if ( $d{'RECORD'} eq '5' );
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		my $cmpd="P ".($d{'LOCATIONCOUNT'}||0)." 0 1 ".($d{'LINEWIDTH'}||1)."0 ";
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f)-$relx;
		  my $y=($d{'Y'.$i}*$f)-$rely;
		  ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  $cmpd.="$x $y ";
		}
		drawcomponent "$cmpd $fill\n";
	  }
	  elsif($d{'RECORD'} eq '7') #Polygon
	  {
	    #RECORD= 7|OWNERPARTID=   1|OWNERINDEX=3856|AREACOLOR=16711680|ISSOLID=T|LINEWIDTH=1|LOCATIONCOUNT=3|OWNERINDEX=3856|X1=450|X2=460|X3=470|Y1=980|Y2=970|Y3=980|
        my $lwidth=defined($d{'LINEWIDTH'})?$d{'LINEWIDTH'}*10:10;
		my $cmpd="P ".($d{'LOCATIONCOUNT'}+1)." 0 1 $lwidth ";
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f)-$relx;
		  my $y=($d{'Y'.$i}*$f)-$rely;
		  ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  $cmpd.="$x $y ";
		}
        my $x=($d{'X1'}*$f)-$relx;
		my $y=($d{'Y1'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		$cmpd.="$x $y $fill\n";
		drawcomponent "$cmpd";
	  }
	  elsif($d{'RECORD'} eq '8') # Ellipse
	  {
	    #RECORD= 8|OWNERPARTID=   1|OWNERINDEX=3899|AREACOLOR=16711680|ISSOLID=T|LINEWIDTH=1|LOCATION.X=376|LOCATION.Y=1109|OWNERINDEX=3899|RADIUS=1|SECONDARYRADIUS=1|print "RECORD7: $filename\n";
        my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		my $LINEWIDTH=$d{LINEWIDTH}||1;
		drawcomponent "C $x $y ".(($d{'RADIUS'}||0)*$f)." 0 1 $LINEWIDTH"."0 $fill\n";
	  }
      elsif($d{'RECORD'} eq '12' || $d{'RECORD'} eq '11') # Arc or Elliptical arc (we average the axes as KiCad doesn't support it)
	  {
	    #RECORD=12|ENDANGLE=180.000|LINEWIDTH=1|LOCATION.X=1065|LOCATION.Y=700|OWNERINDEX=738|RADIUS=5|STARTANGLE=90.000|		
        my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $r=int((($d{'RADIUS'}||0)+(($d{'RADIUS_FRAC'}||0)/100000.0))*$f);
		my $sa="0"; $sa="$1$2" if(defined($d{'STARTANGLE'}) && $d{'STARTANGLE'}=~m/(\d+)\.(\d)(\d+)/);
		my $ea="3600"; $ea="$1$2" if(defined($d{'ENDANGLE'}) && $d{'ENDANGLE'}=~m/(\d+)\.(\d)(\d+)/);
        if ( $d{'RECORD'} eq '11' )
        {
            my $sc=int((($d{'SECONDARYRADIUS'}||0)+(($d{'SECONDARYRADIUS_FRAC'}||0)/100000.0))*$f);
            $r=($r+$sc)/2;
            print "WARNING: Elliptical arcs are not supported in KiCad - creating circular arc using average radius instead\n";
        }
        $ea+=3600 if ( $sa > $ea );
		my @liste=();
		if(($ea-$sa)>=1800)
		{
		  # Altium Angles larger than 180 degrees have to be split up in 2 that are each less than 180 degrees, since KiCad cannot handle them.
		  #print "We have to split $sa->$ea\n";
		  push @liste,[$sa,int($sa+($ea-$sa)/3)];
		  push @liste,[int($sa+($ea-$sa)/3),int($sa+2*($ea-$sa)/3)];
		  push @liste,[int($sa+2*($ea-$sa)/3),$ea];
		}
		else
		{
		  push @liste,[$sa,$ea];
		}
        #print "Liste:\n";
		foreach(@liste)
		{
		  my ($sa,$ea)=@$_;
		  #print "  $sa $ea\n";
		  #print "partorient: $partorientation{$globalp}, winkel: ".$winkel{$partorientation{$globalp}&3}."\n";
		  $sa=3600-$winkel{($partorientation{$globalp}||0)&3}*10+$sa;$sa%=3600; $sa-=3600 if($sa>1800);
		  $ea=3600-$winkel{($partorientation{$globalp}||0)&3}*10+$ea;$ea%=3600; $ea-=3600 if($ea>1800);
		  #print "sa: $sa ea:$ea\n";
		  my $sarad=$sa/1800*$pi;
		  my $earad=$ea/1800*$pi;
		  my $x1=int($x+cos($sarad)*$r);
		  my $x2=int($x+cos($earad)*$r);
		  my $y1=int($y+sin($sarad)*$r);
		  my $y2=int($y+sin($earad)*$r);
		  my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		  drawcomponent "A $x $y $r $sa $ea 1 1 $d{LINEWIDTH}0 $fill $x1 $y1 $x2 $y2\n";
		}
      }
	  elsif($d{'RECORD'} eq '41') # Text / Designator?
	  {
	    #RECORD=41|OWNERPARTID=1|OWNERINDEX=1568|LOCATION.X=80|LOCATION.Y=846|NAME=Comment|OWNERINDEX=1568|TEXT=2.1mm x 5.5mm DC jack|
		#RECORD=41|OWNERPARTID=1|OWNERINDEX=219|LOCATION.X=514|LOCATION.Y=144|NAME=>NAME|ORIENTATION=2|COLOR=8388608|FONTID=3|TEXT=R39|UNIQUEID=MCQTJAIN|NOTAUTOPOSITION=T|INDEXINSHEET=7

		my $x=(($d{'LOCATION.X'}||0)*$f)-$relx;
		my $y=(($d{'LOCATION.Y'}||0)*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $text=$d{'DESCRIPTION'} || $d{'TEXT'} || ""; $text=~s/\~/~~/g; $text=~s/\~1/\~/g; $text=~s/ /\~/g; 
		if($d{'NOTAUTOPOSITION'})
		{
     	  my $rot=$d{'ORIENTATION'} || $myrot{$fontrotation{$d{'FONTID'}}};
          my $size=$fontsize{$d{'FONTID'}}*6;
		  my $bold=$fontbold{$d{'FONTID'}}?"12":"0";
          print OUT "Text Notes ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." $rot    $size   ~ $bold\n$text\n" if($text ne "" && $text ne " ");
          #$dat="Text Notes $x ".($sheety-$y)." $rot    $size   ~ $bold\n$text\n" if($text ne "" && $text ne " ");  
		}
		else
		{
		  drawcomponent "T 0 $x $y 50 0 1 1 $text 1\n";
		}
	  }
	  elsif($d{'RECORD'} eq '10') # Oval???
	  {
	    print "This could be oval or rounded rectangle\n";
        #RECORD=10|OWNERINDEX=934|ISNOTACCESIBLE=T|INDEXINSHEET=1|OWNERPARTID=1|LOCATION.X=870|LOCATION.Y=245|CORNER.X=900|CORNER.Y=265|CORNERXRADIUS=2|CORNERXRADIUS_FRAC=48596|CORNERYRADIUS=3|CORNERYRADIUS_FRAC=39613|COLOR=16711680|ISSOLID=T
	    #RECORD=14|OWNERPARTID=   8|OWNERINDEX=  27|AREACOLOR=11599871|CORNER.X=310|CORNER.Y=1370|ISSOLID=T|LINEWIDTH=2|LOCATION.X=140|LOCATION.Y=920|OWNERINDEX=27|TRANSPARENT=T|
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		drawcomponent "S $x $y $cx $cy 0 1 10 f\n";
      }
	  elsif($d{'RECORD'} eq '29') # Junction
	  {
	    #RECORD=29|OWNERPARTID=  -1|OWNERINDEX=   0|LOCATION.X=130|LOCATION.Y=1230|
		my $px=($d{'LOCATION.X'}*$f);
		my $py=($sheety-$d{'LOCATION.Y'}*$f);
		print OUT "Connection ~ $px $py\n";
	  }
  	  elsif($d{'RECORD'} eq '1')  # Schematic Component
	  {
        #RECORD= 1|OWNERPARTID=  -1|OWNERINDEX=   0|AREACOLOR=11599871|
		#COMPONENTDESCRIPTION=4-port multiple-TT hub with USB charging support|CURRENTPARTID=1|DESIGNITEMID=GLI8024-48_4|DISPLAYMODECOUNT=1|LIBRARYPATH=*|
		#LIBREFERENCE=GLI8024-48_4|
		#LOCATION.X=1380|LOCATION.Y=520|PARTCOUNT=2|PARTIDLOCKED=F|SHEETPARTFILENAME=*|SOURCELIBRARYNAME=*|TARGETFILENAME=*|
		$LIBREFERENCE=$d{'LIBREFERENCE'}; $LIBREFERENCE=~s/ /_/g;
		$LIBREFERENCE.="_".$d{'CURRENTPARTID'} if($d{'PARTCOUNT'}>2);
		$CURRENTPARTID=$d{'CURRENTPARTID'} || undef;
		$OWNERPARTDISPLAYMODE=$d{'DISPLAYMODE'};
		$OWNERLINENO=$d{'LINENO'};
		$globalp++;
		$nextxypos=($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f);
		$partorientation{$globalp}=$d{'ORIENTATION'}||0;
		$partorientation{$globalp}+=4 if(defined($d{'ISMIRRORED'}) && $d{'ISMIRRORED'} eq 'T');
        $xypos{$globalp}=$nextxypos ;
		$relx=$d{'LOCATION.X'}*$f;
		$rely=$d{'LOCATION.Y'}*$f;
	  }
	  else
	  {
	    print "Unhandled Record type within: $d{RECORD}\n";
	  }
	
      push @{$parts{$globalp}},$dat;
	  $partcomp{$globalp}=$LIBREFERENCE;
      $dat="";	  
	}
    else # Not a component
	{
	  
	  if($d{'RECORD'} eq '4') # Label
	  {
	    #|RECORD=4|LOCATION.X=40|TEXT=I2C mappings:|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|LOCATION.Y=500|FONTID=3
		my $size=$fontsize{$d{'FONTID'}}*6;
		my $bold=$fontbold{$d{'FONTID'}}?"12":"0";
		my $rot=$d{'ORIENTATION'} || $myrot{$fontrotation{$d{'FONTID'}}};
		#print "FONTROT: $fontrotation{$d{'FONTID'}}\n" if($text=~m/0xA/);
		my $text=$d{'TEXT'}||"";
        if ( substr($text,0,1) eq '=' ) # It's an xref - look it up
        {
            my $paramname = substr($text,1);
            $text = $globalparams{lc($paramname)} || $text;
        }
        $text=~s/\~/~~/g; $text=~s/\n/\\n/gs;
	    $dat="Text Notes ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." $rot    $size   ~ $bold\n$text\n" if($text ne "" && $text ne " ");
	  }
	  elsif($d{'RECORD'} eq '12') # Arc
	  {
	    print "This circle/arc is not part of a component, but KiCad does not support that. As a workaround we are creating a dummy component.\n";
		# TODO: Dummy creation
	  }
	  elsif($d{'RECORD'} eq '15') # Sheet Symbol
	  {
	    #|SYMBOLTYPE=Normal|RECORD=15|LOCATION.X=40|ISSOLID=T|YSIZE=30|OWNERPARTID=-1|COLOR=128|INDEXINSHEE=41|AREACOLOR=8454016|XSIZE=90|LOCATION.Y=230|UNIQUEID=OLXGMUHL
		$symbol="\$Sheet\nS ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'XSIZE'}*$f)." ".($d{'YSIZE'}*$f);
	    #$dat="\$Sheet\nS ".($symbolx)." ".($symboly)." ".($symbolsizex)." ".($d{'YSIZE'}*$f)."\nF0 \"$prevname\" 60\nF1 \"$prevfilename\" 60\n\$EndSheet\n";
        $relx=$d{'LOCATION.X'}*$f;
        $rely=$d{'LOCATION.Y'}*$f;
        $relw=$d{'XSIZE'}*$f;
        $relh=$d{'YSIZE'}*$f;
	  }
	  elsif($d{'RECORD'} eq '32') # Sheet Name
	  {
	    #|RECORD=32|LOCATION.X=40|TEXT=U_02cpu_power|OWNERINDEX=42|OWNERPARTID=-1|COLOR=8388608|INDEXINSHEET=-1|LOCATION.Y=240|FONTID=1
		#These Texts are transferred to the Sheet Symbol, and do not need to be duplicated here:
	    #$dat="Text Label ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." 0    60   ~ 0\n".$d{'TEXT'}."\n";
        $prevname=$d{'TEXT'}; $prevname=~s/"/'/g;
      }
	  elsif($d{'RECORD'} eq '33') # Sheet Symbol
	  {
        $prevfilename=$d{'TEXT'} if($d{'RECORD'} eq '33'); $prevfilename=~s/\.SchDoc/-SchDoc\.sch/i;	
	    $dat="$symbol\nF0 \"$prevname\" 60\nF1 \"$prevfilename\" 60\n\$EndSheet\n";
		$rootlibraries{"$short-cache.lib"}=1;
	  }	  
	  elsif($d{'RECORD'} eq '27') # Wire
	  {
	    #|RECORD=27|Y2=190|LINEWIDTH=1|X2=710|LOCATIONCOUNT=2|X1=720|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|Y1=190
		my $prevx=undef; my $prevy=undef;
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f);
		  my $y=$sheety-($d{'Y'.$i}*$f);
    	  $dat.=#"Text Label $x $y 0 60 ~\n$d{LINENO}\n".
		  "Wire Wire Line\n	$x $y $prevx $prevy\n" if(defined($prevx));
          $prevx=$x;
		  $prevy=$y;
		}
	  }
	  elsif($d{'RECORD'} eq '13') # Line
	  {
	    #|RECORD=13|ISNOTACCESIBLE=T|LINEWIDTH=1|LOCATION.X=581|CORNER.Y=1103|OWNERPARTID=1|OWNERINDEX=168|CORNER.X=599|COLOR=16711680|LOCATION.Y=1103
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'CORNER.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	  }
	  elsif($d{'RECORD'} eq '17') # Power Object
	  {
	    #RECORD=17|OWNERPARTID=  -1|OWNERINDEX=   0|LOCATION.X=370|LOCATION.Y=1380|ORIENTATION=1|SHOWNETNAME=T|STYLE=2|TEXT=VCC_1.2V_SW1AB|
		my $px=($d{'LOCATION.X'}*$f);
		my $py=($sheety-$d{'LOCATION.Y'}*$f);
		my $py1=$py+140;
		my $py2=$py+110;
		my $text=$d{'TEXT'};
	    my $SHOWNETNAME=$d{'SHOWNETNAME'}?"0000":"00001";
		my $ts=uniqueid2timestamp($d{'UNIQUEID'});
	    my $PWR="L power:GND #PWR?$ts";
		my $voltage=$d{'TEXT'} || "1.2V";
        my $device=$d{'TEXT'} || "+1.2V";
	#print "#TEXT:$d{TEXT} $b\n";
		my %standardvoltages=("5V"=>1,"6V"=>1,"8V"=>1,"9V"=>1,"12V"=>1,"15V"=>1,"24V"=>1,"36V"=>1,"48V"=>1,"3\.3V"=>1);
		if($d{'TEXT'}=~m/(0\.75V|1\.2V|1\.5V|1\.8V|2\.5V|2\.8V|3\.0V|3\.3VA|3\.3V|5\.0V|\d+\.\d+V)/)
		{
		  $voltage=$1;
		  $voltage=~s/\.0//;
		  $device="+".$voltage;
		  #print "Voltage $voltage\n";
		  if(!defined($standardvoltages{$voltage}))
		  {
		    #print "We have to define this voltage: $voltage\n";
			my $voltageC=$voltage."C";
			my $component=$voltageC;
			my $comp=<<EOF
# $voltageC
#
DEF $voltageC #PWR 0 0 Y Y 1 F P
F0 "#PWR" 0 -150 50 H I C CNN
F1 "$voltageC" 0 150 50 H V C CNN
F2 "" 0 0 60 H V C CNN
F3 "" 0 0 60 H V C CNN
DRAW
P 2 0 1 0  -30 50  0 100 N
P 2 0 1 0  0 0  0 100 N
P 2 0 1 0  0 100  30 50 N
X $voltageC 1 0 0 0 U 50 50 1 1 W N
ENDDRAW
ENDDEF
EOF
;
            print LIB $comp unless(defined($localcontains{$component}));
		    $localcontains{$component}=1;
			$globalcomp.=$comp unless(defined($globalcontains{$component}));
	        $globalcontains{$component}=1;
			
		  }
		   
          $componentheader{$device}="#\n# $device\n#\nDEF $device #PWR 0 0 Y Y 1 F P";
          $designatorpos{$device}="\"#PWR\" 0 140 20 H I L BNN";
          $commentpos{$device}="\"$device\" 0 110 30 H V L BNN";
          $componentdraw{$device}=<<EOF
P 3 0 0 0  0 0  0 70  0 70 N
X $device 1 0 0 0 U 20 20 0 0 W N
C 0 60 20 0 1 0 N
EOF
;
		}
		elsif($d{'TEXT'}=~m/(1V0|1V1|1V2|1V5|1V8|1V35|2V5|2V8|3V0|3V3|3V8|4V|5V|6V|8V|9V|10V|12V|15V|24V|28V|36V|48V)/)
		{
		  $voltage=$d{'TEXT'};
		  $device="+".$voltage;
		}
		elsif($d{'TEXT'}=~m/VDD/)
		{
		  $voltage="VDD";
		  $device=$voltage;
		}
		elsif($d{'TEXT'}=~m/GND/)
		{
		  $voltage="GND";
		  $device=$voltage;
		}
		elsif($d{'TEXT'} eq 'VCOREDIG') # This is a workaround for Novena, it could potentially break other schematics
		{
		  $voltage="1.5V";
		  $device="+1.5V";
		}
		else
		{
  		  #print "Unknown Voltage: $d{TEXT}\n";
		  #print "Defining Powerobject:\n";
		  my $voltageC=$voltage;
		  my $component=$voltageC;
		  my $comp=<<EOF
# $voltageC
#
DEF $voltageC #PWR 0 0 Y Y 1 F P
F0 "#PWR" 0 -150 50 H I C CNN
F1 "$voltageC" 0 150 50 H V C CNN
F2 "" 0 0 60 H V C CNN
F3 "" 0 0 60 H V C CNN
DRAW
P 2 0 1 0  -30 50  0 100 N
P 2 0 1 0  0 0  0 100 N
P 2 0 1 0  0 100  30 50 N
X $voltageC 1 0 0 0 U 50 50 1 1 W N
ENDDRAW
ENDDEF
EOF
;
          print LIB $comp unless(defined($localcontains{$component}));
		  $localcontains{$component}=1;
		  $globalcomp.=$comp unless(defined($globalcontains{$component}));
	      $globalcontains{$component}=1;
		  
		}
		
		if(defined($d{'STYLE'}) && ($d{'STYLE'}eq"1" || $d{'STYLE'}eq"2"))
		{
		  $PWR="L power:$device #PWR?$ts"; # $ts";
		  $py1=$py;
		  $py2=$py-70;
		}
        $text=uniquify($text);
        print OUT <<EOF
\$Comp
$PWR
U 1 1 $ts
P $px $py
F 0 "$text" H $px $py1 20  $SHOWNETNAME C CNN
F 1 "$voltage" H $px $py2 30  0000 C CNN
F 2 "" H $px $py 70  0000 C CNN
F 3 "" H $px $py 70  0000 C CNN
	1    $px $py
	1    0    0    -1  
\$EndComp
EOF
;
	  }
	  elsif($d{'RECORD'} eq '29') # Junction
	  {
	    #RECORD=29|OWNERPARTID=  -1|OWNERINDEX=   0|LOCATION.X=130|LOCATION.Y=1230|
		my $px=($d{'LOCATION.X'}*$f);
		my $py=($sheety-$d{'LOCATION.Y'}*$f);
		$dat.="Connection ~ $px $py\n";
	  }
	  elsif($d{'RECORD'} eq '1')  # Schematic Component
	  {
        #RECORD= 1|OWNERPARTID=  -1|OWNERINDEX=   0|AREACOLOR=11599871|
		#COMPONENTDESCRIPTION=4-port multiple-TT hub with USB charging support|CURRENTPARTID=1|DESIGNITEMID=GLI8024-48_4|DISPLAYMODECOUNT=1|LIBRARYPATH=*|
		#LIBREFERENCE=GLI8024-48_4|
		#LOCATION.X=1380|LOCATION.Y=520|PARTCOUNT=2|PARTIDLOCKED=F|SHEETPARTFILENAME=*|SOURCELIBRARYNAME=*|TARGETFILENAME=*|
		$LIBREFERENCE=$d{'LIBREFERENCE'}; $LIBREFERENCE=~s/ /_/g;
		$LIBREFERENCE.="_".$d{'CURRENTPARTID'} if($d{'PARTCOUNT'}>2);
		$CURRENTPARTID=$d{'CURRENTPARTID'} || undef;
		$OWNERPARTDISPLAYMODE=$d{'DISPLAYMODE'};
		$OWNERLINENO=$d{'LINENO'};
		$globalp++;
		$nextxypos=($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f);
		$partorientation{$globalp}=$d{'ORIENTATION'}||0;
		$partorientation{$globalp}+=4 if(defined($d{'ISMIRRORED'}) && $d{'ISMIRRORED'} eq 'T');
        $xypos{$globalp}=$nextxypos ;
		$relx=$d{'LOCATION.X'}*$f;
		$rely=$d{'LOCATION.Y'}*$f;
	  }
	  elsif($d{'RECORD'} eq '5') # Bezier curves, not component related
	  {
        #RECORD= 6|OWNERPARTID=   1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
		my @bezpoints=();
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f);
		  my $y=$sheety-($d{'Y'.$i}*$f);
		  push @bezpoints,$x;
		  push @bezpoints,$y;
		}
		#print "Control: @bezpoints ".scalar(@bezpoints)."\n";
		my $bez=Math::Bezier->new(@bezpoints);
		my @linepoints=$bez->curve(10);
		#print "Bezier: @linepoints\n";
		while(scalar(@linepoints)>=4)
		{
		  my $x1=int(shift(@linepoints));
		  my $y1=int(shift(@linepoints));
	      $dat.="Wire Notes Line\n	".int($linepoints[0])." ".int($linepoints[1])." $x1 $y1\n";
	    }
		
	  }
	  elsif($d{'RECORD'} eq '8') # Ellipse
	  {
        #RECORD=8|LINENO=10947|OWNERPARTID=0|OWNERINDEX=-42|AREACOLOR=16777215|ISSOLID=T|LINEWIDTH=1|LOCATION.X=148|LOCATION.Y=580|RADIUS=3|SECONDARYRADIUS=3|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $radius=int($d{'RADIUS'})*$f;
		my $secondary=int($d{'SECONDARYRADIUS'})*$f; 
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		
		my $parts=40;		
		for(my $i=0;$i<$parts;$i++)
		{
		  my $x1=int($x+sin((2*$pi*$i/$parts))*$radius);
		  my $y1=int($y+cos((2*$pi*$i/$parts))*$secondary);
		  my $x2=int($x+sin((2*$pi*($i+1)/$parts))*$radius);
		  my $y2=int($y+cos((2*$pi*($i+1)/$parts))*$secondary);
    	  $dat.="Wire Notes Line\n	$x1 $y1 $x2 $y2\n";
		}
	    #$dat.="Text Label $x $y 0 60 ~\nELLIPSE\n";        
	  }
	  elsif($d{'RECORD'} eq '11') # Elliptic Arc
	  {
        #RECORD=11|ENDANGLE=87.556|LINEWIDTH=1|LOCATION.X=170|LOCATION.Y=575|RADIUS=8|RADIUS_FRAC=40116|SECONDARYRADIUS=10|SECONDARYRADIUS_FRAC=917|STARTANGLE=271.258|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $radius=int($d{'RADIUS'})*$f;
		my $secondary=int($d{'SECONDARYRADIUS'})*$f; # Primary and Secondary might be mixed up in the calculation
		my $sa=($d{'STARTANGLE'}+90)*$pi/180;
		my $ea=($d{'ENDANGLE'}+90)*$pi/180; $ea+=$pi*2 if($ea<$sa);
		my $ra=$ea-$sa;
		
		my $parts=50;		
		for(my $i=0;$i<$parts;$i++)
		{
		  my $x1=int($x+sin($sa+($ra*$i/$parts))*$radius);
		  my $y1=int($y+cos($sa+($ra*$i/$parts))*$secondary);
		  my $x2=int($x+sin($sa+($ra*($i+1)/$parts))*$radius);
		  my $y2=int($y+cos($sa+($ra*($i+1)/$parts))*$secondary);
    	  $dat.="Wire Notes Line\n	$x1 $y1 $x2 $y2\n";
		}
	    #$dat.="C $x $y $radius 0 0 $d{LINEWIDTH}\n";
    	#$dat.="Text Label $x $y 0 60 ~\nELLIPSE\n"; 
	  }	  
	  elsif($d{'RECORD'} eq "6") # Polyline
	  {
        #RECORD=6|OWNERPARTID=1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
		my $prevx=undef; my $prevy=undef;
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=(($d{'X'.$i}||0)*$f);
		  my $y=$sheety-(($d{'Y'.$i}||0)*$f);
    	  $dat.="Wire Notes Line\n	$x $y $prevx $prevy\n" if(defined($prevx));
          $prevx=$x;
		  $prevy=$y;
		}
	  }
	  elsif($d{'RECORD'} eq '25') #Net Label
	  {
        #RECORD=25|OWNERPARTID=  -1|OWNERINDEX=   0|LINENO=2658|LOCATION.X=1420|LOCATION.Y=230|TEXT=PMIC_INT_B|
        my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		my $orientation=$d{'ORIENTATION'} || 0;
        my $size=$fontsize{$d{'FONTID'}}*6;
        my $name=$d{'TEXT'}||"";  $name=~s/((.\\)+)/\~$1\~/g; $name=~s/(.)\\/$1/g; 
    	$dat.="Text Label $x $y $orientation $size ~\n$name\n" if($d{'TEXT'} ne "");
      }
	  elsif($d{'RECORD'} eq '34') #Designator
	  {
        #RECORD=34|OWNERPARTID=  -1|OWNERINDEX=  27|LINENO=146|LOCATION.X=600|LOCATION.Y=820|NAME=Designator|OWNERINDEX=27|TEXT=U200|COLOR=8388608|FONTID=3
	        my ($x, $y, $orient, $dir) = get_f_position(%d, $f, $partorientation{$globalp}, $relx, $rely, $sheety);

		my $desig="IC"; $desig=$1 if($d{'TEXT'}=~m/^([A-Z]*)/);
		my $ref=uniquify($d{'TEXT'}); $ref=~s/"/'/g;

		push @{$parts{$globalp}},"F 0 \"$ref\" $orient $x $y 60  0000 $dir\n"; # L BNN\n";

		$x=($d{'LOCATION.X'}*$f)-$relx;
		$y=($d{'LOCATION.Y'}*$f)-$rely;
		$globalreference{$globalp}=$ref;
		$designatorpos{$LIBREFERENCE}="\"$desig\" $x $y 60 H V L BNN"; # $desig 70 H V L BNN
      }
	  elsif($d{'RECORD'} eq '41') #Parameter
	  {
        #RECORD=41|OWNERPARTID=  -1|OWNERINDEX=2659|ISHIDDEN=T|LINENO=2661|LOCATION.X=1400|LOCATION.Y=260|NAME=PinUniqueId|OWNERINDEX=2659|TEXT=DXTGJKVR|
        #RECORD=41|OWNERINDEX=1293|INDEXINSHEET=-1|OWNERPARTID=-1|LOCATION.X=845|LOCATION.Y=310|COLOR=8388608|FONTID=1|TEXT==Value|NAME=Comment|UNIQUEID=ROAWIONW
		#my $ts=uniqueid2timestamp($d{'UNIQUEID'});
	    #print "UNIQ: $d{UNIQUEID} -> $ts\n";
        $partparams{lc($d{'NAME'})}=$d{'TEXT'};
        if ( !( defined($d{'ISHIDDEN'}) && $d{'ISHIDDEN'} eq 'T') )
        {
          if(($d{'NAME'}||"") eq "Comment")
          {
            my ($x, $y, $orient, $dir) = get_f_position(%d, $f, $partorientation{$globalp}, $relx, $rely, $sheety);

            #$dat.="Text Label $x $y $orientation 70 ~\n$d{TEXT}\n";
            if ( defined($d{'TEXT'}) )
            {
                my $value = $d{'TEXT'}; 
                if ( substr($value,0,1) eq '=' ) # It's an xref - look it up
                {
                    my $paramname = substr($value,1);
                    $value = $partparams{lc($paramname)} || $value;
                }
				$value=~s/"/'/g;
                push @{$parts{$globalp}},"F 1 \"$value\" $orient $x $y 60  0000 $dir\n"; #L BNN
                push @{$parts{$globalp}},"F 2 \"\" H $x $y 60  0000 C CNN\n";
                push @{$parts{$globalp}},"F 3 \"\" H $x $y 60  0000 C CNN\n";
            }

            $x=($d{'LOCATION.X'}*$f)-$relx;
            $y=($d{'LOCATION.Y'}*$f)-$rely;

            $commentpos{$LIBREFERENCE}="\"$LIBREFERENCE\" $x $y 60 $orient V L BNN";
            $globalcomment{$globalp}=$d{'TEXT'};
          }
          elsif(($d{'NAME'}||"") eq "Rule")
          {
            my $x=(($d{'LOCATION.X'} || 0) *$f);
            my $y=$sheety-(($d{'LOCATION.Y'}||0)*$f);
            my $o=$d{'ORIENTATION'} || 0;
            $dat.="Text Label $x $y $o 70 ~\n".($d{'DESCRIPTION'}||"")."\n" if(defined($d{'DESCRIPTION'}) && $d{'DESCRIPTION'} ne "");
          }
          elsif(($d{'NAME'}||"") eq "Value")
          {
              my ($x, $y, $orient, $dir) = get_f_position(%d, $f, $partorientation{$globalp}, $relx, $rely, $sheety);
              if (defined($d{'TEXT'}))
              {
              my $value = $d{'TEXT'}; $value=~s/"/'/g;
              push @{$parts{$globalp}},"F 1 \"$value\" $orient $x $y 60  0000 $dir\n"; #L BNN
              push @{$parts{$globalp}},"F 2 \"\" H $x $y 60  0000 C CNN\n";
              push @{$parts{$globalp}},"F 3 \"\" H $x $y 60  0000 C CNN\n";
              }
          }
          elsif(defined($d{'LOCATION.X'}) && $d{'LOCATION.Y'} >=0 )
          {
            #print "Field $d{'NAME'} found on line 1093\n";
            my $x=(($d{'LOCATION.X'}||0)*$f);
            my $y=$sheety-(($d{'LOCATION.Y'}||0)*$f);
            my $o=$d{'ORIENTATION'} || 0;
            if(defined($d{'TEXT'}))
            {
              #print "globalp: $globalp OWNERINDEX: $d{OWNERINDEX}\n" if($d{'NAME'} eq "MPN"); I am not sure, whether the association through globalp is correct here
              my $counter=$partstextcounter{$globalp} || 4;
			  my $TEXT=$d{'TEXT'}||""; $TEXT=~s/"/'/g;
			  my $NAME=$d{'NAME'}||""; $NAME=~s/"/'/g;
              push @{$parts{$globalp}},"F $counter \"$TEXT\" V 1400 2000 60  0001 C CNN \"$NAME\"\n";
              $partstextcounter{$globalp}=$counter+1;
            }
            $dat.="Text Label $x $y $o 70 ~\n$d{TEXT}\n" if(defined($d{'TEXT'}) && $d{'TEXT'} ne "");
          }
          else
          {
            # Here we are getting Spice, Netlist, ... data. We should do something with that...
            #print "Error: Parameter $d{'NAME'}=$d{'TEXT'} without position!\n" if(defined($d{'TEXT'}) && $d{'TEXT'} ne "*"); 
          }
        }
      }
	  elsif($d{'RECORD'} eq '43') #Comment?
	  {
        #RECORD=41|OWNERPARTID=  -1|OWNERINDEX=2659|ISHIDDEN=T|LINENO=2661|LOCATION.X=1400|LOCATION.Y=260|NAME=PinUniqueId|OWNERINDEX=2659|TEXT=DXTGJKVR|
		if(defined($d{'LOCATION.X'}))
		{
          my $x=($d{'LOCATION.X'}*$f);
		  my $y=$sheety-($d{'LOCATION.Y'}*$f);
		  my $o=$d{'ORIENTATION'} || 0;
    	  $dat.="Text Label $x $y $o 70 ~\n".($d{NAME}||"")."\n";
		}
		else
		{
		  print "Error: Comment without position !\n";
		}
      }
  	  elsif($d{'RECORD'} eq '22') #No ERC
	  {
        #RECORD=22|OWNERPARTID=  -1|OWNERINDEX=   0|ISACTIVE=T|LINENO=1833|LOCATION.X=630|LOCATION.Y=480|SUPPRESSALL=T|SYMBOL=Thin Cross|
        if(defined($d{'LOCATION.X'}))
        {
          my $x=($d{'LOCATION.X'}*$f);
		  my $y=$sheety-($d{'LOCATION.Y'}*$f);
    	  $dat.="NoConn ~ $x $y\n";
        }
        else
        {
          print "Error: No ERC without position !  $b\n";
        }
      }
	  elsif($d{'RECORD'} =~m/^(10|14)$/) # Rectangle
	  {
	    #RECORD=14|OWNERPARTID=   8|OWNERINDEX=  27|AREACOLOR=11599871|CORNER.X=310|CORNER.Y=1370|ISSOLID=T|LINEWIDTH=2|LOCATION.X=140|LOCATION.Y=920|OWNERINDEX=27|TRANSPARENT=T|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		#($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f);
		my $cy=$sheety-($d{'CORNER.Y'}*$f);
		#($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
	    $dat.="Wire Notes Line\n	$x $y $x $cy\n";
	    $dat.="Wire Notes Line\n	$x $y $cx $y\n";
	    $dat.="Wire Notes Line\n	$x $cy $cx $cy\n";
	    $dat.="Wire Notes Line\n	$cx $y $cx $cy\n";

	  }
	  elsif($d{'RECORD'} eq '30') # Image
	  {
	    #RECORD=30|CORNER.X=810|CORNER.X_FRAC=39800|CORNER.Y=59|CORNER.Y_FRAC=99999|FILENAME=C:\largework\electrical\rdtn\cc-logo.tif|KEEPASPECT=T|LINENO=3428|LOCATION.X=790|LOCATION.Y=40|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		#($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f);
		my $cy=$sheety-($d{'CORNER.Y'}*$f);
		my $mx=int(($x+$cx)/2);
		my $widthx=abs($x-$cx);
		my $my=int(($y+$cy)/2);
		#print "x:$x y:$y cx:$cx cy:$cy mx:$mx my:$my\n";
		#($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		if(0)
		{
	      $dat.="Wire Notes Line\n	$x $y $x $cy\n";
	      $dat.="Wire Notes Line\n	$x $y $cx $y\n";
	      $dat.="Wire Notes Line\n	$x $cy $cx $cy\n";
	      $dat.="Wire Notes Line\n	$cx $y $cx $cy\n";
     	  $dat.="Text Label $x $y 0 70 ~\n$d{FILENAME}\n";
		}
        #print "$d{FILENAME}\n";		
		my $bmp=$d{'FILENAME'};$bmp=~s/^.*\\//;
		#print "$bmp\n";
		if(!-f $bmp)
		{
		  print "ERROR: $bmp not found!\n";
		}
		my $png=$bmp; $png=~s/\.\w+$/.png/;
		#print "$bmp -> $png\n";
		if((-f $bmp) && (! -f $png))
		{
		  system "\"$imagemagick"."convert\" -colorspace RGB \"$bmp\" \"$png\"";
		}
		my $identify="identify";
		my $ident="";
		if(-f $png)
		{
		 $ident=`"$imagemagick$identify" "$png"`;
		}
	    my $imagex=1; my $imagey=1;
		if($ident=~m/PNG (\w+)x(\w+)/)
		{
		  $imagex=$1; $imagey=$2;
		}
		my $scale=$widthx/$imagex/3.3; $scale=~s/\./,/;
		#print "$png $imagex $imagey $widthx $scale $ident\n";
		if(-f $png)
		{
		  $dat.="\$Bitmap\nPos $mx $my\nScale $scale\nData\n";
		  my $pngdata=readfile($png);
          foreach(0 .. length($pngdata)-1)
		  {
  		    $dat.=sprintf("%02X ",unpack("C",substr($pngdata,$_,1)));
		    $dat.="\n" if($_%32 ==31);
		  }
		  $dat.="\nEndData\n\$EndBitmap\n";
		}

	  }
	  elsif($d{'RECORD'} eq '28' || $d{'RECORD'} eq '209') # Text Frame
	  {
        sub min ($$) { $_[$_[0] > $_[1]] }
  		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		#my $x=($d{'LOCATION.X'}*$f)-$relx;
		#my $y=($d{'LOCATION.Y'}*$f)-$rely;
        #($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f);
		my $cy=$sheety-($d{'CORNER.Y'}*$f);
		#($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
        my $text=$d{'TEXT'}; $text=~s/\~1/  /g; $text=~s/ /\~/g if ( ($d{'WORDWRAP'}||'N') eq 'N' );
        my $o=$d{'ORIENTATION'} || 0;
        $x=$x<$cx?$x:$cx;
        $y=$y<$cy?$y:$cy;
        my $size=$fontsize{$d{'FONTID'}}*6;
   	    $dat.="Text Label $x $y $o $size ~\n$text\n";
		#drawcomponent "T 0 $x $y 100 0 1 1 $text 1\n";
		#!!! Line-break, Alignment, ...
      }	  
	  elsif($d{'RECORD'} eq '31') #Sheet
	  {
	    # This has been handled already with other code above.
		my $nfonts=$d{'FONTIDCOUNT'};
		foreach(1 ..$nfonts)
		{
		  my $fontname=$d{'FONTNAME'.$_};
		  my $fontsize=$d{'SIZE'.$_}; $fontsize{$_}=$fontsize;
		  my $rotation=$d{'ROTATION'.$_}||"0"; $fontrotation{$_}=$rotation;
		  my $bold=$d{'BOLD'.$_}||""; $fontbold{$_}=$bold;
		  #print "$_:$fontname:$fontsize:$rotation:$bold\n";
		}
	  }
	  elsif($d{'RECORD'} eq '45') # Packaging
	  {
        #RECORD=45|LINENO=2857|OWNERPARTID= -42|OWNERINDEX=2856|DATAFILECOUNT=1|DESCRIPTION=SOT23, 3-Leads, Body 2.9x1.3mm, Pitch 0.95mm, Lead Span 2.5mm, IPC Medium Density|ISCURRENT=T|MODELDATAFILEENTITY0=SOT23-3N|MODELDATAFILEKIND0=PCBLib|MODELNAME=SOT23-3N|MODELTYPE=PCBLIB|	  
	    #print $d{'DESCRIPTION'}."\n" if(defined($d{'DESCRIPTION'}));
	  }
	  elsif($d{'RECORD'} =~m/^(44|46|47|48)$/)
	  {
	    # NOP
	  }
	  elsif($d{'RECORD'} eq '39') # Reference to Schema Template
	  {
	    # References $d{'FILENAME'} as a filepath, but this likely does not exist
	  }
	  elsif($d{'RECORD'} eq '18') # Port
	  {
        #RECORD=18|INDEXINSHEET=75|OWNERPARTID=-1|STYLE=3|IOTYPE=1|ALIGNMENT=1|WIDTH=60|LOCATION.X=510|LOCATION.Y=990|COLOR=128|FONTID=1|AREACOLOR=8454143|TEXTCOLOR=128|NAME=ADC_VIN|UNIQUEID=ANXOUWEQ|HEIGHT=10
        #RECORD=18|INDEXINSHEET=73|OWNERPARTID=-1|STYLE=3|ALIGNMENT=1|WIDTH=45|LOCATION.X=625|LOCATION.Y=325|COLOR=128|FONTID=1|AREACOLOR=8454143|TEXTCOLOR=128|NAME=GPIO_IF|HARNESSTYPE=GPIO|UNIQUEID=RNYSNNOD|HEIGHT=10
        # No support for HARNESSTYPE yet (KiCad doesn't have such a feature)  We could instantiate lots of Ports as per the .Hardness file definition, but how would we lay them out?
        my $x=($d{'LOCATION.X'}*$f);
        my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $orientation=($d{'ALIGNMENT'}||0)>2 ? 0:2; # Altium seems to ignore this for harnesses?
        my $shape=$iotypes{$d{'IOTYPE'} || 0 }; # Altium never seems to write out IOTYPE=0 for BiDi's
        #$x += $d{'WIDTH'}*10 ; # WRONG for ports on the "right side" of components (which need to be taggead as 'left' types too) - but we can't know that, as it's not encoded in the Altium file!
        print "WARNING: Port orientation may be incorrect and thus unconnected - ports on the 'left' of wires may need moving and orientation flipping\n";
        my $name=$d{'NAME'}; $name=~s/((.\\)+)/\~$1\~/g; $name=~s/(.)\\/$1/g; 
        my $labeltype="GLabel";
        my $size=$fontsize{$d{'FONTID'}}*6;
        $name.="_HARN", $labeltype="HLabel" if ( defined($d{'HARNESSTYPE'}) ); # Annotated bodge for missing harness feature
        $dat.="Text $labeltype ".int($x)." ".int($y)." $orientation $size ${shape} ~\n${name}\n";
	  }
	  elsif($d{'RECORD'} eq '16') # sheet entry
	  {
        # RECORD=16|OWNERINDEX=70|OWNERPARTID=-1|SIDE=1|DISTANCEFROMTOP=4|DISTANCEFROMTOP_FRAC1=500000|COLOR=128|AREACOLOR=8454143|TEXTCOLOR=128|TEXTFONTID=1|TEXTSTYLE=Full|NAME=POR|UNIQUEID=WKEEFSHT|IOTYPE=1|STYLE=3|ARROWKIND=Block & Triangle
        # RECORD=16|OWNERINDEX=77|OWNERPARTID=-1|SIDE=1|DISTANCEFROMTOP=21|COLOR=128|AREACOLOR=8454143|TEXTCOLOR=128|TEXTFONTID=1|TEXTSTYLE=Full|NAME=Ethernet_IF|HARNESSTYPE=Ethernet|UNIQUEID=TVQYSGEL|STYLE=3|ARROWKIND=Block & Triangle
        # Sides are: 0=left, 1=right, 2=top, 3=bottom - only left/right tested
        my $x=$relx;
        my $y=$sheety-$rely;
        my $distance=(($d{'DISTANCEFROMTOP'}||0)*10+($d{'DISTANCEFROMTOP_FRAC1'}||0)/100000.0)*$f;
        my $side=$d{'SIDE'}||0;
        my $shape=$iotypes{$d{'IOTYPE'} || 0 };
        my $name=$d{'NAME'};  $name=~s/((.\\)+)/\~$1\~/g; $name=~s/(.)\\/$1/g; 
        my $orient=0;
        $orient = 2, $y+=$distance            if ( $side eq '0' );
        $orient = 0, $y+=$distance, $x+=$relw if ( $side eq '1' );
        $orient = 3, $x+=$distance            if ( $side eq '2' );
        $orient = 1, $x+=$distance, $y+=$relh if ( $side eq '3' );
        $name.="_HARN" if ( defined($d{'HARNESSTYPE'}) ); # Annotated bodge for missing harness feature
        my $size=$fontsize{$d{'TEXTFONTID'}}*6;
        $dat.="Text HLabel ".int($x)." ".int($y)." ${orient} $size ${shape} ~\n${name}\n";
	  }
  	  elsif($d{'RECORD'} eq '37') # Entry Wire Line / Bus connector
	  {
		my $x1=($d{'LOCATION.X'}*$f);
		my $y1=$sheety-($d{'LOCATION.Y'}*$f);
  		my $x2=($d{'CORNER.X'}*$f);
		my $y2=$sheety-($d{'CORNER.Y'}*$f);
		$dat.="Entry Wire Line\n 	$x1 $y1 $x2 $y2\n";
	  }
  	  elsif($d{'RECORD'} eq '26') # BUS POLYLINE 
	  {
	    #|RECORD=26|INDEXINSHEET=606|OWNERPARTID=-1|LINEWIDTH=2|COLOR=8388608|LOCATIONCOUNT=2|X1=270|Y1=860|X2=215|Y2=860
		foreach my $i(1 .. $d{'LOCATIONCOUNT'}-1)
		{
  		  my $x1=($d{'X'.$i}*$f);
		  my $y1=$sheety-($d{'Y'.$i}*$f);
  		  my $x2=($d{'X'.($i+1)}*$f);
		  my $y2=$sheety-($d{'Y'.($i+1)}*$f);
		  $dat.="Wire Bus Line\n	$x1 $y1 $x2 $y2\n";
		}
	  }
	  else
	  {
	    print "Unhandled Record type without: $d{RECORD}  (#$d{LINENO})\n";
	  }

      print OUT $dat unless(defined($d{'ISHIDDEN'}) && ($d{'ISHIDDEN'} eq 'T'));
	}

  }
  foreach my $part (sort keys %parts)
  {
    next if(!defined($partcomp{$part}));
    print OUT "\$Comp\n";
	#print "Reference: $part -> $globalreference{$part}\n";
	print OUT "L $partcomp{$part} ".($globalreference{$part}||"IC$ICcount")."\n"; # IC$ICcount\n";
	my $ts=uniqueid2timestamp($ICcount);
    print OUT "U 1 1 $ts\n";
    print OUT "P $xypos{$part}\n";
    print OUT $_ foreach(sort @{$parts{$part}});
	print OUT "\t1    $xypos{$part}\n";
	my %orient=("0"=>"1    0    0    -1","3"=>"0    1    1    0","2"=>"-1   0    0    1","1"=>"0    -1   -1   0",
	            "4"=>"-1    0    0    -1","5"=>"0    -1    1    0","6"=>"1   0    0    1","7"=>"0    1   -1   0");
		
	print OUT "\t".$orient{$partorientation{$part}}."\n";
	print OUT "\$EndComp\n";
	$ICcount++;
  }  
  
  foreach my $component (sort keys %componentdraw)
  {
    my $comp="#\n# $component\n#\nDEF $component IC 0 40 Y Y 1 F N\n";
	$comp.="F0 ".($designatorpos{$component}||"\"IC\" 0 0 60 H V C CNN")."\n";
    $comp.="F1 ".($commentpos{$component}||"\"\" 0 0 60 H V C CNN")."\n";
    $comp.="F2 \"\" 0 0 60 H V C CNN\n";
    $comp.="F3 \"\" 0 0 60 H V C CNN\n";
	$comp.=$customfields{$component}||""; # "F 4 "MEINMPN0192301923" V 1400 2000 60  0001 C CNN "MPN"
    $comp.="DRAW\n";
	$comp.=$componentdraw{$component}||"";
	$comp.="ENDDRAW\nENDDEF\n";
	$globalcomp.=$comp unless(defined($globalcontains{$component}));
	$globalcontains{$component}=1;
	print LIB $comp;
  }
  
  print OUT "\$EndSCHEMATC";
  close OUT;
  close LOG if($USELOGGING);
  print LIB "#End Library\n";
  close LIB;
}

foreach my $lib(sort keys %rootlibraries)
{
  #print "Rewriting Root Library $lib\n";
  open LIB,">$lib";
  my $timestamp=strftime("%d.%m.%Y %H:%M:%S", localtime($start_time));
  print LIB "EESchema-LIBRARY Version 2.3  Date: $timestamp\n#encoding utf-8\n";
  print LIB $globalcomp;
  print LIB "#End Library\n";
  close LIB;
}
