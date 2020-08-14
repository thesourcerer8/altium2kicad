#!/usr/bin/perl -w
use strict;
use Compress::Zlib;
use Cwd qw();
use Encode qw/encode decode/;
use File::Glob qw(:globally :nocase);

# This tool unpacks Microsoft Composite Document File V2
# It was developed based on the documentation from 
# http://www.openoffice.org/sc/compdocfileformat.pdf

# All *.SchDoc and *.PcbDoc in the current directory are read, and subdirectories with the same name are created and all contents of those files are written into those subdirectories.

my @files=<*.SchDoc>;
push @files,<*.PcbDoc>;
push @files,<*.IntLib>;
push @files,<*.PcbLib>;
push @files,<*.SchLib>;
push @files,<*.CMSchDoc>;
push @files,<*.CMPcbDoc>;
push @files,<*.CMSchLib>;
push @files,<*.CMPcbLib>;

my $debug=$ARGV[0] || 0;

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

@files=@ARGV if(defined($ARGV[0]) && -f $ARGV[0]);

foreach my $file (@files)
{
  #next if($file=~m/^ASCII/i); # We have to skip ASCII formatted PCB Files
  next if(-d $file); # We only handle files, no directories.
  print "Loading $file\n";
  my $short=$file; $short=~s/\.(\w+)$/-$1/;
  $short=~s/\x13//g;
  mkdir $short;
  open IN,"<$file";
  binmode IN;
  undef $/;
  my $content=<IN>;
  
  if(substr($content,0,length("|RECORD=Board|")) eq "|RECORD=Board|")
  {
    print "Skipping ASCII .PcbDoc\n";
    next;
  }
  print "filelength: ".length($content)."\n" if($debug);
  
  close IN;

  my %visits=();

  my $v="l";

  our $header=substr($content,0,512);
  our $CDFident=substr($header,0,8);
  our $uid=substr($header,8,16);
  our $revision=unpack('v',substr($header,24,2));
  our $version=unpack('v',substr($header,26,2));
  our $byteorder=substr($header,28,2);
  our $sectorpowersize=unpack('v',substr($header,30,2));
  our $sectorsize=2**$sectorpowersize;
  our $shortsectorpowersize=unpack('v',substr($header,32,2));
  our $shortsectorsize=2**$shortsectorpowersize;
  our $unused=substr($header,34,10);
  our $SATsizeSectors=unpack($v,substr($header,44,4));
  our $SecIdDirStream=unpack($v,substr($header,48,4));
  our $unused2=substr($header,52,4);
  our $minByteSizeStdStream=unpack($v,substr($header,56,4));
  our $SecIdSSAT=unpack($v,substr($header,60,4));
  our $totalSectorsSSAT=unpack($v,substr($header,64,4));
  our $SecIdMSAT=unpack($v,substr($header,68,4));
  our $totalSectorsMSAT=unpack($v,substr($header,72,4));
  our $firstpartMSAT=substr($header,76,436);
  
  next unless($revision==62); # We might stumble across other ASCII files that way

  our $MSAT=$firstpartMSAT;
  if($debug)
  {
    print "maximum number of blocks: ".((length($content)-512)/$sectorsize)."\n";
    #print "header: $header\n";
    print "CDFident: ".bin2hex($CDFident)."\n";
    print "uid: ".bin2hex($uid)."\n";
    print "revision: $revision\n";
    print "version: $version\n";
    print "byteorder: ".unpack("n",$byteorder)."\n";
    print "sectorpowersize: $sectorpowersize\n";
    print "sectorsize: $sectorsize\n";
    print "shortsectorpowersize: $shortsectorpowersize\n";
    print "shortsectorsize: $shortsectorsize\n";
    print "unused: ".bin2hex($unused)."\n";
    print "SATsizeSectors: $SATsizeSectors\n";
    print "SecIdDirStream: $SecIdDirStream\n";
    print "unused2: ".bin2hex($unused2)."\n";
    print "minByteSizeStdStream: $minByteSizeStdStream\n";
    print "SecIdSSAT: $SecIdSSAT\n";
    print "totalSectorsSSAT: $totalSectorsSSAT\n";
    print "SecIdMSAT: $SecIdMSAT\n";
    print "totalSectorsMSAT: $totalSectorsMSAT\n";
    #print "firstpartMSAT: $firstpartMSAT\n";
    print "filelength: ".length($content)."\n";
    print "maximum number of blocks: ".((length($content)-512)/$sectorsize)."\n";
  } 
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
      if((512+($nextsec*$sectorsize))>length($content))
      {
        print "CollectingMSAT(): Error in file $file: next sector in MSAT goes beyond end of file!\n";
        last;
      }
      #print "Adding a MSAT block at $nextsec->".(512+$nextsec*$sectorsize)." ($sectorsize)\n";
      my $sec=substr($content,512+($nextsec*$sectorsize),$sectorsize);
      $MSAT.=substr($sec,0,$sectorsize-4);
      $nextsec=unpack($v,substr($sec,-4,4));
      print "nextsec: $nextsec\n" if($debug);
    }
  }
  my @MSAT=();
  foreach(0 .. (length($MSAT)/4)-1)
  {
    push @MSAT,unpack($v,substr($MSAT,$_*4,4));
  }
  if($debug)
  {
    print "MSAT logged to log_msat.txt\n";
    open MSAT ,">log_msat.txt";
    print MSAT join(",",@MSAT)."\n";
    close MSAT;
    print "sectorsize: $sectorsize\n";
  }


  # Collecting the whole SAT Table:
  my @SAT=();
  my $SAT1="";
  foreach(@MSAT)
  {
    if($_>=0)
    { 
      my $sec=substr($content,512+($_*$sectorsize),$sectorsize);
      $SAT1.=$sec;
    }
  }
  foreach(0 .. (length($SAT1)/4)-1)
  {
    push @SAT,unpack($v,substr($SAT1,$_*4,4));
  }

  if($debug)
  {
    print "SAT logged to log_sat.txt\n";
    open SAT ,">log_sat.txt";
    print SAT join(",",@SAT)."\n";
    close SAT;
  }

  sub getLongFile($$$$$)
  {
    my $nextsec=$_[0];
    my @SAT=@{$_[2]};
    my $file=$_[3];
    my $content=$_[4];
    my $filecontent="";
    my %seen=();
    my $count=0;
	
    #print "sectorsize: $sectorsize\n";

    while($nextsec>=0)
    {
      #print "count:$count nextsec:$nextsec sectorsize:$sectorsize nextpos:".(512+($nextsec*$sectorsize))." length(content):".length($content)."\n";
      if((512+($nextsec*$sectorsize))>length($content))
      {
        print "getLongFile(): Error in file $file: next sector $nextsec in file goes beyond end of file beginning sector: $_[0]!\n";
        return "";
      }

      $visits{$nextsec+1}=1;
      my $sec=substr($content,512+($nextsec*$sectorsize),$sectorsize);
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

  #print "sectorsize: $sectorsize\n";
  
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
      #print "nextsec: $nextsec\n" if($debug);
    }
    #print "getShortFile() retrieved ".length($filecontent)." of $_[1] requested bytes\n";

    return $_[1]>0?substr($filecontent,0,$_[1]):$filecontent;
  }



  #print "Collecting the whole ShortSAT Table:\n";
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
      if(512+($nextsec*$sectorsize)>length($content))
      {
        print "CollectingShortSAT(): Error in file $file: next sector in SSAT goes beyond end of file!\n";
      }
      my $sec=substr($content,512+($nextsec*$sectorsize),$sectorsize);
      $SSAT.=substr($sec,0,$sectorsize);
      #print "SAT[$nextsec]=$SAT[$nextsec]\n";
      $nextsec=$SAT[$nextsec];
      #print "nextsec: $nextsec\n";
    }
  }
  #print "Done with SSAT.\n";
  #print "Loading SSAT2 from $SecIdSSAT\n";
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
  if($debug)
  {
    print "SSAT logged to log_ssat.txt\n";
    open SSAT ,">log_ssat.txt";
    print SSAT join(",",@SSAT)."\n";
    close SSAT;
  }

  my $DirStream=getLongFile($SecIdDirStream,0,\@SAT,$file,$content);
  my @DirStream=();
  
  open OUT,">$short.manifest.txt" if($debug);
  foreach(0 .. (length($DirStream)/128)-1)
  {
    my $DirEntry=substr($DirStream,$_*128,128);
    #print OUT bin2hex($DirEntry)." ";
    my $namesize=unpack("v",substr($DirEntry,64,2));
    my $type=unpack("C",substr($DirEntry,66,1));
    my $name=decode("UCS-2LE",substr($DirEntry,0,$namesize)); $name=~s/\x00//g;
    my $nodecolour=unpack("C",substr($DirEntry,67,1));
    my $DirIdLeftChild=unpack($v,substr($DirEntry,68,4));
    my $DirIdRightChild=unpack($v,substr($DirEntry,72,4));
    my $DirIdRootNode=unpack($v,substr($DirEntry,76,4));
    my $SecIdStream=unpack($v,substr($DirEntry,116,4));
    my $totalbytes=unpack($v,substr($DirEntry,120,4));

    print OUT "$type $nodecolour left:$DirIdLeftChild right:$DirIdRightChild root:$DirIdRootNode sec:$SecIdStream bytes:$totalbytes $name\n" if($debug);
    push @DirStream,$DirEntry;
  }
  close OUT if($debug);

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
    my $namesize=unpack("v",substr($DirEntry,64,2));
    my $name=decode("UCS-2LE",substr($DirEntry,0,$namesize)); $name=~s/\x00//g;
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

    print "DirStream[$_[1]]: name:$name t:$type c:$nodecolour left:$DirIdLeftChild right:$DirIdRightChild root:$DirIdRootNode flags:$flags start:$SecIdStream total:$totalbytes\n" if($debug);
    #print "creation: ".bin2hex($tstampcreation)." modification: ".bin2hex($tstamplastmod)."\n" if($debug);
    #print "Name: $name namesize: $namesize\n" if($debug);
    #exit if(length($name) != $namesize/2-1 && $type);
    

    #print "Making $path\n" if($debug);
    $path=~s/\x13//g;
    mkdir $path;

    my $bytes="";
    if($type==5)
    {
      #print "\nShort Stream in Root storage detected!\n\n";
      $ShortStream=getLongFile($SecIdStream,0,\@SAT,$file,$content); 
      $bytes=$ShortStream;
    }
    elsif($totalbytes>=$minByteSizeStdStream)
    {
      #print "Standard Stream detected\n";
      $bytes=getLongFile($SecIdStream,$totalbytes,\@SAT,$file,$content);
    }
    else
    {
      #print "Short Stream detected $name\n";
      $bytes=getShortFile($SecIdStream,$totalbytes,\@SSAT,$file,$ShortStream);
    }
    #print "Bytes: $bytes\n";


    if($DirIdRootNode>=0)
    {
      HandleColor(\@DirStream,$DirIdRootNode,$path."/".$name,$file,\@SAT,$content,\@SSAT,$ShortStream);
    }
    HandleColor(\@DirStream,$DirIdLeftChild,$path,$file,\@SAT,$content,\@SSAT,$ShortStream) if($DirIdLeftChild>=0);
    HandleColor(\@DirStream,$DirIdRightChild,$path,$file,\@SAT,$content,\@SSAT,$ShortStream) if($DirIdRightChild>=0);

    return if($type==5); # Ignore ROOT Block, which contains the ShortStream
     
    my $fname="$path/$name.dat";
	$fname=~s/\x13//g;
     
    if(open(OUT,">$fname"))
    {
      binmode OUT;
      print OUT $bytes;
      close OUT;  
      my $f=$bytes;
      $f=~s/\r\n/\n/sg;
      if(open(OUT,">$fname.bin"))
      {
        binmode OUT;
        print OUT $f;
        close OUT;
      }
      $fname.=".unzip";
      $fname=~s/\.unzip$/.step/ if($fname=~m/\/Models\/\d+\.dat/);
      $fname=~s/0\.pcblib\.dat\.unzip$/0.PcbLib/;
      $fname=~s/0\.schlib\.dat\.unzip$/0.SchLib/;
      if(substr($f,0,2) eq "\x02\x78")
      {
        my $x = inflateInit();
        my $dest = $x->inflate(substr($bytes,1));
        open OUT,">$fname";
        binmode OUT;
        print OUT $dest;
        close OUT;
      } 
      if(substr($f,0,1) eq "\x78")
      {
        my $x = inflateInit();
        my $dest = $x->inflate($bytes);
        open OUT,">$fname";
        binmode OUT;
        print OUT $dest;
        close OUT;
      }
      if($fname=~m/^(.*)0\.(Pcb|Sch)Lib$/)
      {
        my $newpath=$1;
        my $path = Cwd::cwd();
        chdir $newpath;
        my $newerpath = Cwd::cwd();

        print "Path: $path Newpath: $newpath Newerpath: $newerpath 0: $0\n" if($debug);
        #system "\"$0\""; ENDLESS LOOP, make sure to prevent that before re-enabling it
	chdir $path;
      }
    }
    else
    {
      print "HandleColor() Error when writing $fname: $!\n";
    }
    #print "\n";

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
  print "\n";
}
print "Done.\n";
sleep(1);
