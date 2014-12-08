#!/usr/bin/perl -w
use strict;
use Compress::Zlib;

# This tool unpacks Microsoft Composite Document File V2
# It was developed based on the documentation from 
# http://www.openoffice.org/sc/compdocfileformat.pdf

# All *.SchDoc and *.PcbDoc in the current directory are read, and subdirectories with the same name are created and all contents of those files are written into those subdirectories.

my @files=<*.SchDoc>;
push @files,<*.PcbDoc>;
push @files,<*.IntLib>;
push @files,<*.PcbLib>;
push @files,<*.SchLib>;

foreach my $file (@files)
{
  next if($file=~m/^ASCII/i); # We have to skip ASCII formatted PCB Files
  next if(-d $file); # We only handle files, no directories.
  print "Loading $file\n";
  my $short=$file; $short=~s/\.\w+$//;
  mkdir $short;
  open IN,"<$file";
  binmode IN;
  undef $/;
  my $content=<IN>;
  print "filelength: ".length($content)."\n";
  
  close IN;

  my %visits=();

  my $v="l";

  my $header=substr($content,0,512);
  my $CDFident=substr($header,0,8);
  my $uid=substr($header,8,16);
  my $revision=unpack('v',substr($header,24,2));
  my $version=unpack('v',substr($header,26,2));
  my $byteorder=substr($header,28,2);
  my $sectorpowersize=unpack('v',substr($header,30,2));
  my $sectorsize=2**$sectorpowersize;
  my $shortsectorpowersize=unpack('v',substr($header,32,2));
  my $shortsectorsize=2**$shortsectorpowersize;
  my $unused=substr($header,34,10);
  my $SATsizeSectors=unpack($v,substr($header,44,4));
  my $SecIdDirStream=unpack($v,substr($header,48,4));
  my $unused2=substr($header,52,4);
  my $minByteSizeStdStream=unpack($v,substr($header,56,4));
  my $SecIdSSAT=unpack($v,substr($header,60,4));
  my $totalSectorsSSAT=unpack($v,substr($header,64,4));
  my $SecIdMSAT=unpack($v,substr($header,68,4));
  my $totalSectorsMSAT=unpack($v,substr($header,72,4));
  my $firstpartMSAT=substr($header,76,436);

  my $MSAT=$firstpartMSAT;
  print "maximum number of blocks: ".((length($content)-512)/$sectorsize)."\n";

  #print "header: $header\n";
  #print "CDFident: $CDFident\n";
  #print "uid: $uid\n";
  print "revision: $revision\n";
  print "version: $version\n";
  print "byteorder: ".unpack("n",$byteorder)."\n";
  print "sectorpowersize: $sectorpowersize\n";
  print "sectorsize: $sectorsize\n";
  print "shortsectorpowersize: $shortsectorpowersize\n";
  print "shortsectorsize: $shortsectorsize\n";
  #print "unused: $unused\n";
  print "SATsizeSectors: $SATsizeSectors\n";
  print "SecIdDirStream: $SecIdDirStream\n";
  #print "unused2: $unused2\n";
  print "minByteSizeStdStream: $minByteSizeStdStream\n";
  print "SecIdSSAT: $SecIdSSAT\n";
  print "totalSectorsSSAT: $totalSectorsSSAT\n";
  print "SecIdMSAT: $SecIdMSAT\n";
  print "totalSectorsMSAT: $totalSectorsMSAT\n";
  #print "firstpartMSAT: $firstpartMSAT\n";
  print "filelength: ".length($content)."\n";
  print "maximum number of blocks: ".((length($content)-512)/$sectorsize)."\n";
 
  # Collecting the whole MSAT Table:
  if($totalSectorsMSAT)
  {
    my $n=$totalSectorsMSAT;
    my $nextsec=$SecIdMSAT;
    while($n-- > 0)
    {
      if($nextsec<0)
      {
        print "CollectingMSAT(): Error in file $file, next sector in MSAT is $nextsec but should be a positive value!\n";
        last;
      }
      if(512+$nextsec*$sectorsize>length($content))
      {
        print "CollectingMSAT(): Error in file $file: next sector in MSAT goes beyond end of file!\n";
        last;
      }
	  print "Adding a MSAT block at $nextsec->".(512+$nextsec*$sectorsize)." ($sectorsize)\n";
      my $sec=substr($content,512+$nextsec*$sectorsize,$sectorsize);
      $MSAT.=substr($sec,0,$sectorsize-4);
      $nextsec=unpack($v,substr($sec,-4,4));
      #print "nextsec: $nextsec\n";
    }
  }
  my @MSAT=();
  foreach(0 .. (length($MSAT)/4)-1)
  {
    push @MSAT,unpack($v,substr($MSAT,$_*4,4));
  }
  print "MSAT logged to log_msat.txt\n";
  open MSAT ,">log_msat.txt";
  print MSAT join(",",@MSAT)."\n";
  close MSAT;


  # Collecting the whole SAT Table:
  my @SAT=();
  my $SAT1="";
  foreach(@MSAT)
  {
    if($_>=0)
    { 
      my $sec=substr($content,512+$_*$sectorsize,$sectorsize);
      $SAT1.=$sec;
    }
  }
  foreach(0 .. (length($SAT1)/4)-1)
  {
    push @SAT,unpack($v,substr($SAT1,$_*4,4));
  }

  print "SAT logged to log_sat.txt\n";
  open SAT ,">log_sat.txt";
  print SAT join(",",@SAT)."\n";
  close SAT;
  

  sub getLongFile($$$$$)
  {
    my $nextsec=$_[0];
    my @SAT=@{$_[2]};
    my $file=$_[3];
    my $content=$_[4];
    my $filecontent="";
    my %seen=();
    my $count=0;
    while($nextsec>=0)
    {
      #print "count:$count nextsec:$nextsec\n";
      if(512+$nextsec*$sectorsize>length($content))
      {
        print "getLongFile(): Error in file $file: next sector $nextsec in file goes beyond end of file beginning sector: $_[0]!\n";
        return "";
      }

      $visits{$nextsec+1}=1;
      my $sec=substr($content,512+$nextsec*$sectorsize,$sectorsize);
      $filecontent.=substr($sec,0,$sectorsize);
      #print "oldnextsec: $nextsec SAT[$nextsec]=$SAT[$nextsec]\n";
      $nextsec=$SAT[$nextsec];
      if(defined($seen{$nextsec}))
      {
        print "Circular reference in file $file, starting with sector $_[0]!\n";
      }
      $seen{$nextsec}=1;
      #print "nextsec: $nextsec\n";
      $count++;
    }
    #print "getLongFile() retrieved ".length($filecontent)." of $_[1] requested bytes\n";
    return $_[1]>0?substr($filecontent,0,$_[1]):$filecontent;
  }


  my @SSAT=();

  sub getShortFile($$$$$)
  {
    my $nextsec=$_[0];
    my @SSAT=@{$_[2]};
    my $file=$_[3];
    my $ShortStream=$_[4];

    my $filecontent="";
    my %seen=();
    while($nextsec>=0)
    {
      if($nextsec*$shortsectorsize>length($ShortStream))
      {
        print "getShortFile(): Error in file $file: next short sector in file goes beyond end of Short Stream (".length($ShortStream)."), beginning sector: $_[0]!\n";
        return "";
      }
      my $sec=substr($ShortStream,$nextsec*$shortsectorsize,$shortsectorsize);
      $filecontent.=$sec;
      $nextsec=$SSAT[$nextsec];
      if(defined($seen{$nextsec}))
      {
        print "Circular reference in short file in $file, starting with short sector $_[0]!\n";
      }
      $seen{$nextsec}=1;
      #print "nextsec: $nextsec\n";
    }
    print "getShortFile() retrieved ".length($filecontent)." of $_[1] requested bytes\n";

    return $_[1]>0?substr($filecontent,0,$_[1]):$filecontent;
  }



  print "Collecting the whole ShortSAT Table:\n";
  my $SSAT="";
  if($totalSectorsSSAT>0)
  {
    my $n=$totalSectorsSSAT;
    my $nextsec=$SecIdSSAT;
    while($n-->0)
    {
      #print "n:$n nextsec: $nextsec\n";
      if($nextsec<0)
      {
        print "CollectingShortSAT(): Error in file $file, next sector in SSAT is $nextsec but should be a positive value!\n";
      }
      if(512+$nextsec*$sectorsize>length($content))
      {
        print "CollectingShortSAT(): Error in file $file: next sector in SSAT goes beyond end of file!\n";
      }
      my $sec=substr($content,512+$nextsec*$sectorsize,$sectorsize);
      $SSAT.=substr($sec,0,$sectorsize);
      print "SAT[$nextsec]=$SAT[$nextsec]\n";
      $nextsec=$SAT[$nextsec];
      #print "nextsec: $nextsec\n";
    }
  }
  print "Done with SSAT.\n";
  print "Loading SSAT2 from $SecIdSSAT\n";
  my $SSAT2=getLongFile($SecIdSSAT,0,\@SAT,$file,$content);

  if($SSAT ne $SSAT2)
  {
    print "SSAT and SSAT2 differ!\n";
    open OUT,">$short/SSAT";
    print OUT $SSAT;
    close OUT;
    open OUT,">$short/SSAT2";
    print OUT $SSAT2;
    close OUT;
  }
  foreach(0 .. (length($SSAT)/4)-1)
  {
    push @SSAT,unpack($v,substr($SSAT,$_*4,4));
  }
  
  print "SSAT logged to log_ssat.txt\n";
  open SSAT ,">log_ssat.txt";
  print SSAT join(",",@SSAT)."\n";
  close SSAT;
  

  my $DirStream=getLongFile($SecIdDirStream,0,\@SAT,$file,$content);
  my @DirStream=();
  foreach(0 .. (length($DirStream)/128)-1)
  {
    my $DirEntry=substr($DirStream,$_*128,128);
    push @DirStream,$DirEntry;
  }
 

  sub HandleColor
  {
    my @DirStream=@{$_[0]};
    my $DirEntry=$DirStream[$_[1]];
    my $path=$_[2];
    my $file=$_[3];
    my @SAT=@{$_[4]};
    my $content=$_[5];
    my @SSAT=@{$_[6]};
    my $ShortStream=$_[7];

	return unless defined($DirEntry);
    my $name=substr($DirEntry,0,64); $name=~s/\x00//g;
    my $namesize=substr($DirEntry,64,2);
    my $type=unpack("C",substr($DirEntry,66,1));
    my $nodecolour=unpack("C",substr($DirEntry,67,1));
    my $DirIdLeftChild=unpack($v,substr($DirEntry,68,4));
    my $DirIdRightChild=unpack($v,substr($DirEntry,72,4));
    my $DirIdRootNode=unpack($v,substr($DirEntry,76,4));
    my $UID=substr($DirEntry,80,16);
    my $flags=unpack($v,substr($DirEntry,96,4));
    my $tstampcreation=substr($DirEntry,100,8);
    my $tstamplastmod=substr($DirEntry,108,8);
    my $SecIdStream=unpack($v,substr($DirEntry,116,4));
    my $totalbytes=unpack($v,substr($DirEntry,120,4));
    my $unused=substr($DirEntry,124,4);

    print "DirStream[$_[1]]: name:$name t:$type c:$nodecolour left:$DirIdLeftChild right:$DirIdRightChild root:$DirIdRootNode flags:$flags start:$SecIdStream total:$totalbytes\n";


    print "Making $path\n";
    mkdir $path;

    my $bytes="";
    if($type==5)
    {
      print "Short Stream in Root storage detected!\n";
      $ShortStream=getLongFile($SecIdStream,0,\@SAT,$file,$content); 
      $bytes=$ShortStream;
    }
    elsif($totalbytes>=$minByteSizeStdStream)
    {
      print "Standard Stream detected\n";
      $bytes=getLongFile($SecIdStream,$totalbytes,\@SAT,$file,$content);
    }
    else
    {
      print "Short Stream detected\n";
      $bytes=getShortFile($SecIdStream,$totalbytes,\@SSAT,$file,$ShortStream);
    }
    #print "Bytes: $bytes\n";


    if($DirIdRootNode>=0)
    {
      HandleColor(\@DirStream,$DirIdRootNode,$path."/".$name,$file,\@SAT,$content,\@SSAT,$ShortStream);
    }
    HandleColor(\@DirStream,$DirIdLeftChild,$path,$file,\@SAT,$content,\@SSAT,$ShortStream) if($DirIdLeftChild>=0);
    HandleColor(\@DirStream,$DirIdRightChild,$path,$file,\@SAT,$content,\@SSAT,$ShortStream) if($DirIdRightChild>=0);


     
    if(open(OUT,">$path/$name.dat"))
    {
      binmode OUT;
      print OUT $bytes;
      close OUT;  
      my $f=$bytes;
      $f=~s/\r\n/\n/sg;
      if(open(OUT,">$path/$name.bin"))
      {
        binmode OUT;
        print OUT $f;
        close OUT;
      }
      if(substr($f,0,2) eq "\x02\x78")
      {
        my $x = inflateInit();
        my $dest = $x->inflate(substr($f,1));
        open OUT,">$path/$name.unzip";
        binmode OUT;
        print OUT $dest;
        close OUT;
     } 
     if(substr($f,0,1) eq "\x78")
     {
        my $x = inflateInit();
        my $dest = $x->inflate($f);
        open OUT,">$path/$name.unzip";
        binmode OUT;
        print OUT $dest;
        close OUT;
      } 
    }
    else
    {
      print "HandleColor() Error when writing $path/$name.dat: $!\n";
    }

    print "\n";

  }   

  HandleColor(\@DirStream,0,$short,$file,\@SAT,$content,\@SSAT,"");

if(0)
{
    open OUT,">$short.html";
    print OUT "<html><body><h1>$file</h1><br/><table border='1'>";
    foreach my $sec (0 .. length($content)/512-1)
    {
      my $color=$visits{$sec}?'#80ff80':'#ff8080';
      print OUT "<tr><td bgcolor='$color'><pre>";
      my $a="";
      foreach my $line (0 .. 512/16-1)
      {
        foreach my $char(0 .. 15)
        {
          my $c=substr($content,$sec*512+$line*16+$char,1);
          my $d=unpack("C",$c);
          print OUT sprintf("%02X ",$d);
          $a.=sprintf("\&#%d;",$d);
        }
        print OUT "<br/>"; $a.="<br/>";
      }
      print OUT "</td><td>$a</td></tr>";
    }
    print OUT "</table></body></html>";
    close OUT;
}

}
print "Done.\n";
sleep(1);
