#! /usr/bin/perl

my $dpkglibdir = ".";
my $version = "1.3.0"; # This line modified by Makefile

my @filesinarchive;
my %dirincluded;
my %notfileobject;
my $fn;

$diff_ignore_default_regexp = '(?:^|/).*~$|(?:^|/)\..*\.swp|DEADJOE|(?:/CVS|/RCS|/.deps)(?:$|/.*$)';

$sourcestyle = 'X';
$dscformat = "1.0";

use POSIX;
use POSIX qw (:errno_h :signal_h);

use strict 'refs';

push (@INC, $dpkglibdir);
require 'controllib.pl';

# Make sure patch doesn't get any funny ideas
delete $ENV{'POSIXLY_CORRECT'};

my @exit_handlers = ();
sub exit_handler {
	&$_ foreach ( reverse @exit_handlers );
	exit(127);
}
$SIG{'INT'} = \&exit_handler;
$SIG{'HUP'} = \&exit_handler;
$SIG{'QUIT'} = \&exit_handler;

sub usageversion {
    print STDERR
"Debian dpkg-source $version.  Copyright (C) 1996
Ian Jackson and Klee Dienes.  This is free software; see the GNU
General Public Licence version 2 or later for copying conditions.
There is NO warranty.

Usage:  dpkg-source -x <filename>.dsc
        dpkg-source -b <directory> [<orig-directory>|<orig-targz>|\'\']
Build options:   -c<controlfile>     get control info from this file
                 -l<changelogfile>   get per-version info from this file
                 -F<changelogformat> force change log format
                 -V<name>=<value>    set a substitution variable
                 -T<varlistfile>     read variables here, not debian/substvars
                 -D<field>=<value>   override or add a .dsc field and value
                 -U<field>           remove a field
                 -W                  Turn certain errors into warnings. 
                 -E                  When -W is enabled, -E disables it.
                 -sa                 auto select orig source (-sA is default)
                 -i[<regexp>]        filter out files to ignore diffs of.
                                     Defaults to: '$diff_ignore_default_regexp'
                 -I<filename>        filter out files when building tarballs.
                 -sk                 use packed orig source (unpack & keep)
                 -sp                 use packed orig source (unpack & remove)
                 -su                 use unpacked orig source (pack & keep)
                 -sr                 use unpacked orig source (pack & remove)
                 -ss                 trust packed & unpacked orig src are same
                 -sn                 there is no diff, do main tarfile only
                 -sA,-sK,-sP,-sU,-sR like -sa,-sp,-sk,-su,-sr but may overwrite
Extract options: -sp (default)       leave orig source packed in current dir
                 -sn                 do not copy original source to current dir
                 -su                 unpack original source tree too
General options: -h                  print this message
";
}

sub handleformat {
	local $fmt	= shift;
	local $ourfmt	= $dscformat;

	$fmt =~ s/(.*)\.\d*/$1/;
	$ourfmt =~ s/(.*)\.\d*/$1/;

	return ($fmt==$ourfmt);
}


$i = 100;
grep ($fieldimps {$_} = $i--,
      qw (Format Source Version Binary Origin Maintainer Architecture
      Standards-Version Build-Depends Build-Depends-Indep Build-Conflicts
      Build-Conflicts-Indep));

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_=shift(@ARGV);
    if (m/^-b$/) {
        &setopmode('build');
    } elsif (m/^-x$/) {
        &setopmode('extract');
    } elsif (m/^-s([akpursnAKPUR])$/) {
        $sourcestyle= $1;
    } elsif (m/^-c/) {
        $controlfile= $';
    } elsif (m/^-l/) {
        $changelogfile= $';
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat=$1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
        $override{$1}= $';
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1}= 1;
    } elsif (m/^-i(.*)$/) {
        $diff_ignore_regexp = $1 ? $1 : $diff_ignore_default_regexp;
    } elsif (m/^-I(.+)$/) {
        push @tar_ignore, "--exclude=$1";
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
        $substvar{$1}= $';
    } elsif (m/^-T/) {
        $varlistfile= $';
    } elsif (m/^-h$/) {
        &usageversion; exit(0);
    } elsif (m/^-W$/) {
        $warnable_error= 1;
    } elsif (m/^-E$/) {
        $warnable_error= 0;
    } elsif (m/^--$/) {
        last;
    } else {
        &usageerr("unknown option $_");
    }
}

defined($opmode) || &usageerr("need -x or -b");

$SIG{'PIPE'} = 'DEFAULT';

if ($opmode eq 'build') {

    $sourcestyle =~ y/X/A/;
    $sourcestyle =~ m/[akpursnAKPUR]/ ||
        &usageerr("source handling style -s$sourcestyle not allowed with -b");

    @ARGV || &usageerr("-b needs a directory");
    @ARGV<=2 || &usageerr("-b takes at most a directory and an orig source argument");
    $dir= shift(@ARGV);
    $dir= "./$dir" unless $dir =~ m:^/:; $dir =~ s,/*$,,;
    stat($dir) || &error("cannot stat directory $dir: $!");
    -d $dir || &error("directory argument $dir is not a directory");

    $changelogfile= "$dir/debian/changelog" unless defined($changelogfile);
    $controlfile= "$dir/debian/control" unless defined($controlfile);
    
    &parsechangelog;
    &parsecontrolfile;
    $f{"Format"}=$dscformat;

    $archspecific=0;
    for $_ (keys %fi) {
        $v= $fi{$_};
        if (s/^C //) {
            if (m/^Source$/i) { &setsourcepackage; }
            elsif (m/^(Standards-Version|Origin|Maintainer|Uploaders)$/i) { $f{$_}= $v; }
	    elsif (m/^Build-(Depends|Conflicts)(-Indep)?$/i) { $f{$_}= $v; }
            elsif (s/^X[BC]*S[BC]*-//i) { $f{$_}= $v; }
            elsif (m/^(Section|Priority|Files|Bugs)$/i || m/^X[BC]+-/i) { }
            else { &unknown('general section of control info file'); }
        } elsif (s/^C(\d+) //) {
            $i=$1; $p=$fi{"C$i Package"};
            push(@binarypackages,$p) unless $packageadded{$p}++;
            if (m/^Architecture$/) {
                if ($v eq 'any') {
                    @sourcearch= ('any');
                } elsif ($v eq 'all') {
                    if (!@sourcearch || $sourcearch[0] eq 'all') {
                        @sourcearch= ('all');
                    } else {
                        @sourcearch= ('any');
                    }
                } else {
		    if (grep($sourcearch[0] eq $_, 'any','all'))  {
			@sourcearch= ('any');
		    } else {
                        for $a (split(/\s+/,$v)) {
                            &error("architecture $a only allowed on its own".
                                   " (list for package $p is \`$a')")
                                   if grep($a eq $_, 'any','all');
                            push(@sourcearch,$a) unless $archadded{$a}++;
                        }
                }
                }
                $f{'Architecture'}= join(' ',@sourcearch);
            } elsif (s/^X[BC]*S[BC]*-//i) {
                $f{$_}= $v;
            } elsif (m/^(Package|Essential|Pre-Depends|Depends|Provides)$/i ||
                     m/^(Recommends|Suggests|Optional|Conflicts|Replaces)$/i ||
                     m/^(Description|Section|Priority)$/i ||
                     m/^X[CS]+-/i) {
            } else {
                &unknown("package's section of control info file");
            }
        } elsif (s/^L //) {
            if (m/^Source$/) {
                &setsourcepackage;
            } elsif (m/^Version$/) {
                $f{$_}= $v;
            } elsif (s/^X[BS]*C[BS]*-//i) {
                $f{$_}= $v;
            } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/i ||
                     m/^X[BS]+-/i) {
            } else {
                &unknown("parsed version of changelog");
            }
        } else {
            &internerr("value from nowhere, with key >$_< and value >$v<");
        }
    }

    $f{'Binary'}= join(', ',@binarypackages);
    for $f (keys %override) { $f{&capit($f)}= $override{$f}; }

    for $f (qw(Version)) {
        defined($f{$f}) || &error("missing information for critical output field $f");
    }
    for $f (qw(Maintainer Architecture Standards-Version)) {
        defined($f{$f}) || &warn("missing information for output field $f");
    }
    defined($sourcepackage) || &error("unable to determine source package name !");
    $f{'Source'}= $sourcepackage;
    for $f (keys %remove) { delete $f{&capit($f)}; }

    $version= $f{'Version'};
    $version =~ s/^\d+://; $upstreamversion= $version; $upstreamversion =~ s/-[^-]*$//;
    $basenamerev= $sourcepackage.'_'.$version;
    $basename= $sourcepackage.'_'.$upstreamversion;
    $basedirname= $basename;
    $basedirname =~ s/_/-/;

    $origdir= "$dir.orig";
    $origtargz= "$basename.orig.tar.gz";
    if (@ARGV) {
        $origarg= shift(@ARGV);
        if (length($origarg)) {
            stat($origarg) || &error("cannot stat orig argument $origarg: $!");
            if (-d _) {
                $origdir= $origarg;
                $origdir= "./$origdir" unless $origdir =~ m,^/,; $origdir =~ s,/*$,,;
                $sourcestyle =~ y/aA/rR/;
                $sourcestyle =~ m/[ursURS]/ ||
                    &error("orig argument is unpacked but source handling style".
                           " -s$sourcestyle calls for packed (.orig.tar.gz)");
            } elsif (-f _) {
                $origtargz= $origarg;
                $sourcestyle =~ y/aA/pP/;
                $sourcestyle =~ m/[kpsKPS]/ ||
                    &error("orig argument is packed but source handling style".
                           " -s$sourcestyle calls for unpacked (.orig/)");
            } else {
                &error("orig argument $origarg is not a plain file or directory");
            }
        } else {
            $sourcestyle =~ y/aA/nn/;
            $sourcestyle =~ m/n/ ||
                &error("orig argument is empty (means no orig, no diff)".
                       " but source handling style -s$sourcestyle wants something");
        }
    }

    if ($sourcestyle =~ m/[aA]/) {
        if (stat("$origtargz")) {
            -f _ || &error("packed orig \`$origtargz' exists but is not a plain file");
            $sourcestyle =~ y/aA/pP/;
        } elsif ($! != ENOENT) {
            &syserr("unable to stat putative packed orig \`$origtargz'");
        } elsif (stat("$origdir")) {
            -d _ || &error("unpacked orig \`$origdir' exists but is not a directory");
            $sourcestyle =~ y/aA/rR/;
        } elsif ($! != ENOENT) {
            &syserr("unable to stat putative unpacked orig \`$origdir'");
        } else {
            $sourcestyle =~ y/aA/nn/;
        }
    }
    $dirbase= $dir; $dirbase =~ s,/?$,,; $dirbase =~ s,[^/]+$,,; $dirname= $&;
    $dirname eq $basedirname || &warn("source directory \`$dir' is not <sourcepackage>".
                                      "-<upstreamversion> \`$basedirname'");
    
    if ($sourcestyle ne 'n') {
        $origdirbase= $origdir; $origdirbase =~ s,/?$,,;
        $origdirbase =~ s,[^/]+$,,; $origdirname= $&;

        $origdirname eq "$basedirname.orig" ||
            &warn(".orig directory name $origdirname is not <package>".
                  "-<upstreamversion> (wanted $basedirname.orig)");
        $tardirbase= $origdirbase; $tardirname= $origdirname;

        $tarname= $origtargz;
        $tarname eq "$basename.orig.tar.gz" ||
            &warn(".orig.tar.gz name $tarname is not <package>_<upstreamversion>".
                  ".orig.tar.gz (wanted $basename.orig.tar.gz)");
    } else {
        $tardirbase= $dirbase; $tardirname= $dirname;
        $tarname= "$basenamerev.tar.gz";
    }

    if ($sourcestyle =~ m/[nurUR]/) {

        if (stat($tarname)) {
            $sourcestyle =~ m/[nUR]/ ||
                &error("tarfile \`$tarname' already exists, not overwriting,".
                       " giving up; use -sU or -sR to override");
        } elsif ($! != ENOENT) {
            &syserr("unable to check for existence of \`$tarname'");
        }

        print("$progname: building $sourcepackage in $tarname\n")
            || &syserr("write building tar message");
        &forkgzipwrite("$tarname.new");
        defined($c2= fork) || &syserr("fork for tar");
        if (!$c2) {
            chdir($tardirbase) || &syserr("chdir to above (orig) source $tardirbase");
            open(STDOUT,">&GZIP") || &syserr("reopen gzip for tar");
            # FIXME: put `--' argument back when tar is fixed
            exec('tar',@tar_ignore,'-cf','-',$tardirname); &syserr("exec tar");
        }
        close(GZIP);
        &reapgzip;
        $c2 == waitpid($c2,0) || &syserr("wait for tar");
        $? && !(WIFSIGNALED($c2) && WTERMSIG($c2) == SIGPIPE) && subprocerr("tar");
        rename("$tarname.new",$tarname) ||
            &syserr("unable to rename \`$tarname.new' (newly created) to \`$tarname'");

    } else {
        
        print("$progname: building $sourcepackage using existing $tarname\n")
            || &syserr("write using existing tar message");
        
    }
    
    addfile("$tarname");

    if ($sourcestyle =~ m/[kpKP]/) {

        if (stat($origdir)) {
            $sourcestyle =~ m/[KP]/ ||
                &error("orig dir \`$origdir' already exists, not overwriting,".
                       " giving up; use -sA, -sK or -sP to override");
	    push @exit_handlers, sub { erasedir($origdir) };
            erasedir($origdir);
	    pop @exit_handlers;
        } elsif ($! != ENOENT) {
            &syserr("unable to check for existence of orig dir \`$origdir'");
        }

        $expectprefix= $origdir; $expectprefix =~ s,^\./,,;
# tar checking is disabled, there are too many broken tar archives out there
# which we can still handle anyway.
#        checktarsane($origtargz,$expectprefix);
        mkdir("$origtargz.tmp-nest",0755) ||
            &syserr("unable to create \`$origtargz.tmp-nest'");
	push @exit_handlers, sub { erasedir("$origtargz.tmp-nest") };
        extracttar($origtargz,"$origtargz.tmp-nest",$expectprefix);
        rename("$origtargz.tmp-nest/$expectprefix",$expectprefix) ||
            &syserr("unable to rename \`$origtargz.tmp-nest/$expectprefix' to ".
                    "\`$expectprefix'");
        rmdir("$origtargz.tmp-nest") ||
            &syserr("unable to remove \`$origtargz.tmp-nest'");
	    pop @exit_handlers;
    }
        
    if ($sourcestyle =~ m/[kpursKPUR]/) {
        
        print("$progname: building $sourcepackage in $basenamerev.diff.gz\n")
            || &syserr("write building diff message");
        &forkgzipwrite("$basenamerev.diff.gz");

        defined($c2= open(FIND,"-|")) || &syserr("fork for find");
        if (!$c2) {
            chdir($dir) || &syserr("chdir to $dir for find");
            exec('find','.','-print0'); &syserr("exec find");
        }
        $/= "\0";

      file:
        while (defined($fn= <FIND>)) {
            $fn =~ s/\0$//;
            next file if $fn =~ m/$diff_ignore_regexp/o;
            $fn =~ s,^\./,,;
            lstat("$dir/$fn") || &syserr("cannot stat file $dir/$fn");
            if (-l _) {
                $type{$fn}= 'symlink';
                &checktype('-l') || next;
                defined($n= readlink("$dir/$fn")) ||
                    &syserr("cannot read link $dir/$fn");
                defined($n2= readlink("$origdir/$fn")) ||
                    &syserr("cannot read orig link $origdir/$fn");
                $n eq $n2 || &unrepdiff2("symlink to $n2","symlink to $n");
            } elsif (-f _) {
                $type{$fn}= 'plain file';
                if (!lstat("$origdir/$fn")) {
                    $! == ENOENT || &syserr("cannot stat orig file $origdir/$fn");
                    $ofnread= '/dev/null';
                } elsif (-f _) {
                    $ofnread= "$origdir/$fn";
                } else {
                    &unrepdiff2("something else","plain file");
                    next;
                }
                defined($c3= open(DIFFGEN,"-|")) || &syserr("fork for diff");
                if (!$c3) {
		    $ENV{'LC_ALL'}= 'C';
		    $ENV{'LANG'}= 'C';
		    $ENV{'TZ'}= 'UTC0';
                    exec('diff','-u',
                         '-L',"$basedirname.orig/$fn",
                         '-L',"$basedirname/$fn",
                         '--',"$ofnread","$dir/$fn"); &syserr("exec diff");
                }
                $difflinefound= 0;
                $/= "\n";
                while (<DIFFGEN>) {
                    if (m/^binary/i) {
                        close(DIFFGEN); $/= "\0";
                        &unrepdiff("binary file contents changed");
                        next file;
                    } elsif (m/^[-+\@ ]/) {
                        $difflinefound=1;
                    } elsif (m/^\\ No newline at end of file$/) {
                        &warn("file $fn has no final newline ".
                              "(either original or modified version)");
                    } else {
                        s/\n$//;
                        &internerr("unknown line from diff -u on $fn: \`$_'");
                    }
                    print(GZIP $_) || &syserr("failed to write to gzip");
                }
                close(DIFFGEN); $/= "\0";
                if (WIFEXITED($?) && (($es=WEXITSTATUS($?))==0 || $es==1)) {
                    if ($es==1 && !$difflinefound) {
                        &unrepdiff("diff gave 1 but no diff lines found");
                    }
                } else {
                    subprocerr("diff on $dir/$fn");
                }
            } elsif (-p _) {
                $type{$fn}= 'pipe';
                &checktype('-p');
            } elsif (-b _ || -c _ || -S _) {
                &unrepdiff("device or socket is not allowed");
            } elsif (-d _) {
                $type{$fn}= 'directory';
            } else {
                &unrepdiff("unknown file type ($!)");
            }
        }
        close(FIND); $? && subprocerr("find on $dir");
        close(GZIP) || &syserr("finish write to gzip pipe");
        &reapgzip;

        defined($c2= open(FIND,"-|")) || &syserr("fork for 2nd find");
        if (!$c2) {
            chdir($origdir) || &syserr("chdir to $origdir for 2nd find");
            exec('find','.','-print0'); &syserr("exec 2nd find");
        }
        $/= "\0";
        while (defined($fn= <FIND>)) {
            $fn =~ s/\0$//;
            next if $fn =~ m/$diff_ignore_regexp/o;
            $fn =~ s,^\./,,;
            next if defined($type{$fn});
            lstat("$origdir/$fn") || &syserr("cannot check orig file $origdir/$fn");
            if (-f _) {
                &warn("ignoring deletion of file $fn");
            } elsif (-d _) {
                &warn("ignoring deletion of directory $fn");
            } elsif (-l _) {
                &warn("ignoring deletion of symlink $fn");
            } else {
                &unrepdiff2('not a file, directory or link','nonexistent');
            }
        }
        close(FIND); $? && subprocerr("find on $dirname");

        &addfile("$basenamerev.diff.gz");

    }

    if ($sourcestyle =~ m/[prPR]/) {
        erasedir($origdir);
    }

    print("$progname: building $sourcepackage in $basenamerev.dsc\n")
        || &syserr("write building message");
    open(STDOUT,"> $basenamerev.dsc") || &syserr("create $basenamerev.dsc");
    &outputclose(1);

    if ($ur) {
        print(STDERR "$progname: unrepresentable changes to source\n")
            || &syserr("write error msg: $!");
        exit(1);
    }
    exit(0);

} else {

    $sourcestyle =~ y/X/p/;
    $sourcestyle =~ m/[pun]/ ||
        &usageerr("source handling style -s$sourcestyle not allowed with -x");

    @ARGV==1 || &usageerr("-x needs exactly one argument, the .dsc");
    $dsc= shift(@ARGV);
    $dsc= "./$dsc" unless $dsc =~ m:^/:;
    $dscdir= $dsc; $dscdir= "./$dscdir" unless $dsc =~ m,^/|^\./,;
    $dscdir =~ s,/[^/]+$,,;

    open(CDATA,"< $dsc") || &error("cannot open .dsc file $dsc: $!");
    &parsecdata('S',-1,"source control file $dsc");
    close(CDATA);

    for $f (qw(Source Version Files)) {
        defined($fi{"S $f"}) ||
            &error("missing critical source control field $f");
    }

    if (defined $fi{'S Format'}) {
	if (not handleformat($fi{'S Format'})) {
	    &error("Unsupported format of .dsc file ($dscformat)");
	}
        $dscformat=$fi{'S Format'};
    }

    $sourcepackage =~ m/[^.0-9]/ &&
        &error("dsc format contains illegal character \`$&'");

    $sourcepackage= $fi{'S Source'};
    $sourcepackage =~ m/[^-+.0-9a-z]/ &&
        &error("source package name contains illegal character \`$&'");
    $sourcepackage =~ m/^[0-9a-z]./ ||
        &error("source package name is too short or starts with non-alphanum");

    $version= $fi{'S Version'};
    $version =~ m/[^-+:.0-9a-zA-Z]/ &&
        &error("version number contains illegal character \`$&'");
    $version =~ s/^\d+://;
    if ($version =~ m/-([^-]+)$/) {
        $baseversion= $`; $revision= $1;
    } else {
        $baseversion= $version; $revision= '';
    }

    $files= $fi{'S Files'};
    for $file (split(/\n /,$files)) {
        next if $file eq '';
        $file =~ m/^([0-9a-f]{32})[ \t]+(\d+)[ \t]+([0-9a-zA-Z][-+:.,=0-9a-zA-Z_]+)$/
            || &error("Files field contains bad line \`$file'");
        ($md5sum{$3},$size{$3},$file) = ($1,$2,$3);
        &setfile(\$tarfile) if $file =~ m/\.tar\.gz$/;
        &setfile(\$difffile) if $file =~ m/\.diff\.gz$/;
    }

    $newdirectory= $sourcepackage.'-'.$baseversion;
    $expectprefix= $newdirectory; $expectprefix.= '.orig' if length($difffile);
    
    length($tarfile) || &error("no tarfile in Files field");
    checkstats($tarfile);
    checkstats($difffile) if length($difffile);

# tar checking is disabled, there are too many broken tar archives out there
# which we can still handle anyway.
#    checktarsane("$dscdir/$tarfile",$expectprefix);

    if (length($difffile)) {
            
        &forkgzipread("$dscdir/$difffile");
        $/="\n";
	$_ = <GZIP>;
        while ($_ || !eof(GZIP)) {
	    # read file header (---/+++ pair)
	    s/\n$// or &error("diff is missing trailing newline");
	    /^--- / or &error("expected ^--- in line $. of diff");
                $fn= $';
                substr($fn,0,length($expectprefix)+1) eq "$expectprefix/" ||
                    &error("diff patches file ($fn) not in expected subdirectory");
                $fn =~ m/\.dpkg-orig$/ &&
                    &error("diff patches file with name ending .dpkg-orig");
                $dirname= $fn;
                if ($dirname =~ s,/[^/]+$,, && !defined($dirincluded{$dirname})) {
		    $dirtocreate{$dirname} = 1;
		}
                defined($notfileobject{$fn}) &&
                    &error("diff patches something which is not a plain file");
                $_= <GZIP>; s/\n$// ||
                    &error("diff finishes in middle of ---/+++ (line $.)");
                $_ eq '+++ '.$newdirectory.substr($fn,length($expectprefix)) ||
                    &error("line after --- for file $fn isn't as expected");
                $filepatched{$fn}++ && &error("diff patches file $fn twice");
	    # read hunks
	    my $hunk = 0;
	    while (($_ = <GZIP>) && !/^--- /) {
		# read hunk header (@@)
		s/\n$// or &error("diff is missing trailing newline");
		next if /^\\ No newline/;
		/^@@ -\d+(,(\d+))? \+\d+(,(\d+))? @\@$/ or
		    &error("Expected ^@@ in line $. of diff");
		my ($olines, $nlines) = ($1 ? $2 : 1, $3 ? $4 : 1);
		++$hunk;
		# read hunk
		while ($olines || $nlines) {
		    $_ = <GZIP> or &error("unexpected end of diff");
		    s/\n$// or &error("diff is missing trailing newline");
		    next if /^\\ No newline/;
		    if (/^ /) { --$olines; --$nlines; }
		    elsif (/^-/) { --$olines; }
		    elsif (/^\+/) { --$nlines; }
		    else { &error("expected [ +-] at start of line $. of diff"); }
		}
	    }
	    $hunk or &error("expected ^\@\@ at line $. of diff");
        }
        close(GZIP);
        
        &reapgzip;
    }

    print("$progname: extracting $sourcepackage in $newdirectory\n")
        || &syserr("write extracting message");
    
    &erasedir($newdirectory);
    &erasedir("$newdirectory.orig");

    mkdir("$expectprefix.tmp-nest",0755)
	|| &syserr("unable to create \`$expectprefix.tmp-nest'");
    system "chmod", "g-s", "$expectprefix.tmp-nest";
    extracttar("$dscdir/$tarfile","$expectprefix.tmp-nest","$expectprefix");
    rename("$expectprefix.tmp-nest/$expectprefix","$expectprefix")
	|| &syserr("unable to rename \`$expectprefix.tmp-nest/$expectprefix' "
		   ."to \`$expectprefix'");
    rmdir("$expectprefix.tmp-nest")
	|| &syserr("unable to remove \`$expectprefix.tmp-nest'");

    for $dircreate (keys %dirtocreate) {
	$dircreatem= "";
	for $dircreatep (split("/",$dirc)) {
	    $dircreatem.= $dircreatep;
	    if (!lstat($dircreatem)) {
		$! == ENOENT || &syserr("cannot stat $dircreatem");
		mkdir($dircreatem,0777)
		    || &syserr("failed to create $dircreatem subdirectory");
	    }
	    else {
		-d _ || &error("diff patches file in directory \`$dircreate',"
			       ." but $dircreatem isn't a directory !");
	    }
	}
    }
    
    if (length($difffile)) {
        rename($expectprefix,$newdirectory) ||
            &syserr("failed to rename newly-extracted $expectprefix to $newdirectory");

        if ($sourcestyle =~ m/u/) {
	    mkdir("$expectprefix.tmp-nest",0755)
		|| &syserr("unable to create \`$expectprefix.tmp-nest'");
	    system "chmod", "g-s", "$expectprefix.tmp-nest";
	    extracttar("$dscdir/$tarfile","$expectprefix.tmp-nest",
		       "$expectprefix");
	    rename("$expectprefix.tmp-nest/$expectprefix","$expectprefix")
		|| &syserr("unable to rename \`$expectprefix.tmp-nest/"
			   ."$expectprefix' to \`$expectprefix'");
	    rmdir("$expectprefix.tmp-nest")
		|| &syserr("unable to remove \`$expectprefix.tmp-nest'");
         } elsif ($sourcestyle =~ m/p/) {
            stat("$dscdir/$tarfile") ||
                &syserr("failed to stat \`$dscdir/$tarfile' to see if need to copy");
            ($dsctardev,$dsctarino) = stat _;
            $dumptar= $sourcepackage.'_'.$baseversion.'.orig.tar.gz';
            if (!stat($dumptar)) {
                $! == ENOENT || &syserr("failed to check destination \`$dumptar'".
                                        " to see if need to copy");
            } else {
                ($dumptardev,$dumptarino) = stat _;
                if ($dumptardev == $dsctardev && $dumptarino == $dsctarino) {
                    $dumptar= '';
                }
            }
            if (length($dumptar)) {
                system('cp','--',"$dscdir/$tarfile","$dumptar");
                $? && subprocerr("cp $dscdir/$tarfile to $dumptar");
            }
        }                

        &forkgzipread("$dscdir/$difffile");
        defined($c2= fork) || &syserr("fork for patch");
        if (!$c2) {
            open(STDIN,"<&GZIP") || &syserr("reopen gzip for patch");
            chdir($newdirectory) || &syserr("chdir to $newdirectory for patch");
	    $ENV{'LC_ALL'}= 'C';
	    $ENV{'LANG'}= 'C';
            exec('patch','-s','-t','-F','0','-N','-p1','-u',
                 '-V','never','-g0','-b','-Z','-z','.dpkg-orig');
            &syserr("exec patch");
        }
        close(GZIP);
        $c2 == waitpid($c2,0) || &syserr("wait for patch");
        $? && subprocerr("patch");
        &reapgzip;

        for $fn (keys %filepatched) {
            $ftr= "$newdirectory/".substr($fn,length($expectprefix)+1).".dpkg-orig";
            unlink($ftr) || &syserr("remove patch backup file $ftr");
        }

        if (!(@s= lstat("$newdirectory/debian/rules"))) {
            $! == ENOENT || &syserr("cannot stat $newdirectory/debian/rules");
            &warn("$newdirectory/debian/rules does not exist");
        } elsif (-f _) {
            chmod($s[2] | 0111, "$newdirectory/debian/rules") ||
                &syserr("cannot make $newdirectory/debian/rules executable");
        } else {
            &warn("$newdirectory/debian/rules is not a plain file");
        }
    }

    $execmode= 0777 & ~umask;
    (@s= stat('.')) || &syserr("cannot stat \`.'");
    $dirmode= $execmode | ($s[2] & 02000);
    $plainmode= $execmode & ~0111;
    $fifomode= ($plainmode & 0222) | (($plainmode & 0222) << 1);
    for $fn (@filesinarchive) {
	$fn=~ s,^$expectprefix,$newdirectory,;
        (@s= lstat($fn)) || &syserr("cannot stat extracted object \`$fn'");
        $mode= $s[2];
        if (-d _) {
            $newmode= $dirmode;
        } elsif (-f _) {
            $newmode= ($mode & 0111) ? $execmode : $plainmode;
        } elsif (-p _) {
            $newmode= $fifomode;
        } elsif (!-l _) {
            &internerr("unknown object \`$fn' after extract (mode ".
                       sprintf("0%o",$mode).")");
        } else { next; }
        next if ($mode & 07777) == $newmode;
        chmod($newmode,$fn) ||
            &syserr(sprintf("cannot change mode of \`%s' to 0%o from 0%o",
                            $fn,$newmode,$mode));
    }
    exit(0);
}

sub checkstats {
    my ($f) = @_;
    my @s;
    my $m;
    open(STDIN,"< $dscdir/$f") || &syserr("cannot read $dscdir/$f");
    (@s= stat(STDIN)) || &syserr("cannot fstat $dscdir/$f");
    $s[7] == $size{$f} || &error("file $f has size $s[7] instead of expected $size{$f}");
    $m= `md5sum`; $? && subprocerr("md5sum $f"); $m =~ s/\n$//;
    $m =~ s/ *-$//; # Remove trailing spaces and -, to work with GNU md5sum
    $m =~ m/^[0-9a-f]{32}$/ || &failure("md5sum of $f gave bad output \`$m'");
    $m eq $md5sum{$f} || &error("file $f has md5sum $m instead of expected $md5sum{$f}");
    open(STDIN,"</dev/null") || &syserr("reopen stdin from /dev/null");
}

sub erasedir {
    my ($dir) = @_;
    if (!lstat($dir)) {
        $! == ENOENT && return;
        &syserr("cannot stat directory $dir (before removal)");
    }
    system 'rm','-rf','--',$dir;
    $? && subprocerr("rm -rf $dir");
    if (!stat($dir)) {
        $! == ENOENT && return;
        &syserr("unable to check for removal of dir \`$dir'");
    }
    &failure("rm -rf failed to remove \`$dir'");
}

use strict 'vars';

sub checktarcpio {

    my ($tarfileread, $wpfx) = @_;
    my ($tarprefix, $c2);

    @filesinarchive = ();

    # make <CPIO> read from the uncompressed archive file
    &forkgzipread ("$tarfileread");
    if (! defined ($c2 = open (CPIO,"-|"))) { &syserr ("fork for cpio"); }
    if (!$c2) {
	$ENV{'LC_ALL'}= 'C';
	$ENV{'LANG'}= 'C';
        open (STDIN,"<&GZIP") || &syserr ("reopen gzip for cpio");
        &cpiostderr;
        exec ('cpio','-0t');
	&syserr ("exec cpio");
    }
    close (GZIP);

    $/ = "\0";
    while (defined ($fn = <CPIO>)) {

        $fn =~ s/\0$//;

	# store printable name of file for error messages
	my $pname = $fn;
	$pname =~ y/ -~/?/c;

        if ($fn =~ m/\n/) {
	    &error ("tarfile \`$tarfileread' contains object with".
		    " newline in its name ($pname)");
	}

	next if ($fn eq '././@LongLink');

	if (! $tarprefix) {
	    if ($fn =~ m/\n/) {
                &error("first output from cpio -0t (from \`$tarfileread') ".
                       "contains newline - you probably have an out of ".
                       "date version of cpio.  GNU cpio 2.4.2-2 is known to work");
	    }
	    $tarprefix = ($fn =~ m,((\./)*[^/]*)[/],)[0];
	    # need to check for multiple dots on some operating systems
	    # empty tarprefix (due to regex failer) will match emptry string
	    if ($tarprefix =~ /^[.]*$/) {
		&error("tarfile \`$tarfileread' does not extract into a ".
		       "directory off the current directory ($tarprefix from $pname)");
	    }
	}

	my $fprefix = substr ($fn, 0, length ($tarprefix));
        my $slash = substr ($fn, length ($tarprefix), 1);
        if ((($slash ne '/') && ($slash ne '')) || ($fprefix ne $tarprefix)) {
	    &error ("tarfile \`$tarfileread' contains object ($pname) ".
		    "not in expected directory ($tarprefix)");
	}

	# need to check for multiple dots on some operating systems
        if ($fn =~ m/[.]{2,}/) {
            &error ("tarfile \`$tarfileread' contains object with".
		    " /../ in its name ($pname)");
	}
        push (@filesinarchive, $fn);
    }
    close (CPIO);
    $? && subprocerr ("cpio");
    &reapgzip;
    $/= "\n";

    my $tarsubst = quotemeta ($tarprefix);

    return $tarprefix;
}

sub checktarsane {

    my ($tarfileread, $wpfx) = @_;
    my ($c2);

    %dirincluded = ();
    %notfileobject = ();

    my $tarprefix = &checktarcpio ($tarfileread, $wpfx);

    # make <TAR> read from the uncompressed archive file
    &forkgzipread ("$tarfileread");
    if (! defined ($c2 = open (TAR,"-|"))) { &syserr ("fork for tar -t"); }
    if (! $c2) {
	$ENV{'LC_ALL'}= 'C';
        $ENV{'LANG'}= 'C';
        open (STDIN, "<&GZIP") || &syserr ("reopen gzip for tar -t");
        exec ('tar', '-vvtf', '-'); &syserr ("exec tar -vvtf -");
    }
    close (GZIP);

    my $efix= 0;
    while (<TAR>) {

        chomp;

        if (! m,^(\S{10})\s,) {
            &error("tarfile \`$tarfileread' contains unknown object ".
                   "listed by tar as \`$_'");
	}
	my $mode = $1;

        $mode =~ s/^([-dpsl])// ||
            &error("tarfile \`$tarfileread' contains object \`$fn' with ".
                   "unknown or forbidden type \`".substr($_,0,1)."'");
        my $type = $&;

        if ($mode =~ /^l/) { $_ =~ s/ -> .*//; }
        s/ link to .+//;

	my @tarfields = split(' ', $_, 6);
	if (@tarfields < 6) { 
	    &error ("tarfile \`$tarfileread' contains incomplete entry \`$_'\n");
	}

	my $tarfn = deoctify ($tarfields[5]);

	# store printable name of file for error messages
	my $pname = $tarfn;
	$pname =~ y/ -~/?/c;

	# fetch name of file as given by cpio
        $fn = $filesinarchive[$efix++];

	my $l = length($fn);
	if (substr ($tarfn, 0, $l + 4) eq "$fn -> ") {
		# This is a symlink, as listed by tar.  cpio doesn't
		# give us the targets of the symlinks, so we ignore this.
		$tarfn = substr($tarfn, 0, $l);
	}
	if ($tarfn ne $fn) {
	    if ((length ($fn) == 99) && (length ($tarfn) >= 99)
		&& (substr ($fn, 0, 99) eq substr ($tarfn, 0, 99))) {
		# this file doesn't match because cpio truncated the name
		# to the first 100 characters.  let it slide for now.
		&warn ("filename \`$pname' was truncated by cpio;" .
		       " unable to check full pathname");
		# Since it didn't match, later checks will not be able
		# to stat this file, so we replace it with the filename
		# fetched from tar.
		$filesinarchive[$efix-1] = $tarfn;
	    } else {
		&error ("tarfile \`$tarfileread' contains unexpected object".
			" listed by tar as \`$_'; expected \`$pname'");
	    }
	}

	# if cpio truncated the name above, 
	# we still can't allow files to expand into /../
	# need to check for multiple dots on some operating systems
        if ($tarfn =~ m/[.]{2,}/) {
            &error ("tarfile \`$tarfileread' contains object with".
		    "/../ in its name ($pname)");
	}

        if ($tarfn =~ /\.dpkg-orig$/) {
            &error ("tarfile \`$tarfileread' contains file with name ending in .dpkg-orig");
	}

        if ($mode =~ /[sStT]/ && $type ne 'd') {
            &error ("tarfile \`$tarfileread' contains setuid, setgid".
		    " or sticky object \`$pname'");
	}

        if ($tarfn eq "$tarprefix/debian" && $type ne 'd') {
            &error ("tarfile \`$tarfileread' contains object \`debian'".
                   " that isn't a directory");
	}

        if ($type eq 'd') { $tarfn =~ s,/$,,; }
        $tarfn =~ s,(\./)*,,;
        my $dirname = $tarfn;

        if (($dirname =~ s,/[^/]+$,,) && (! defined ($dirincluded{$dirname}))) {
            &warnerror ("tarfile \`$tarfileread' contains object \`$pname' but its containing ".
		    "directory \`$dirname' does not precede it");
	    $dirincluded{$dirname} = 1;
	}
	if ($type eq 'd') { $dirincluded{$tarfn} = 1; }
        if ($type ne '-') { $notfileobject{$tarfn} = 1; }
    }
    close (TAR);
    $? && subprocerr ("tar -vvtf");
    &reapgzip;

    my $tarsubst = quotemeta ($tarprefix);
    @filesinarchive = map { s/^$tarsubst/$wpfx/; $_ } @filesinarchive;
    %dirincluded = map { s/^$tarsubst/$wpfx/; $_=>1 } (keys %dirincluded);
    %notfileobject = map { s/^$tarsubst/$wpfx/; $_=>1 } (keys %notfileobject);
}

no strict 'vars';

sub extracttar {
    my ($tarfileread,$dirchdir,$newtopdir) = @_;
    &forkgzipread("$tarfileread");
    defined($c2= fork) || &syserr("fork for tar -xkf -");
    if (!$c2) {
        open(STDIN,"<&GZIP") || &syserr("reopen gzip for tar -xkf -");
        &cpiostderr;
        chdir("$dirchdir") || &syserr("cannot chdir to \`$dirchdir' for tar extract");
        exec('tar','-xkf','-'); &syserr("exec tar -xkf -");
    }
    close(GZIP);
    $c2 == waitpid($c2,0) || &syserr("wait for tar -xkf -");
    $? && subprocerr("tar -xkf -");
    &reapgzip;

    opendir(D,"$dirchdir") || &syserr("Unable to open dir $dirchdir");
    @dirchdirfiles = grep($_ ne "." && $_ ne "..",readdir(D));
    closedir(D) || &syserr("Unable to close dir $dirchdir");
    if (@dirchdirfiles==1 && -d "$dirchdir/$dirchdirfiles[0]") {
	rename("$dirchdir/$dirchdirfiles[0]", "$dirchdir/$newtopdir") ||
	    &syserr("Unable to rename $dirchdir/$dirchdirfiles[0] to ".
	    "$dirchdir/$newtopdir");
    } else {
	mkdir("$dirchdir/$newtopdir", 0777) ||
	    &syserr("Unable to mkdir $dirchdir/$newtopdir");
	for (@dirchdirfiles) {
	    rename("$dirchdir/$_", "$dirchdir/$newtopdir/$_") ||
		&syserr("Unable to rename $dirchdir/$_ to ".
		"$dirchdir/$newtopdir/$_");
	}
    }
}

sub cpiostderr {
    open(STDERR,"| egrep -v '^[0-9]+ blocks\$' >&2") ||
        &syserr("reopen stderr for tar to grep out blocks message");
}

sub setfile {
    my ($varref) = @_;
    if (defined ($$varref)) { 
	&error ("repeated file type - files " . $$varref . " and $file"); 
    }
    $$varref = $file;
}

sub checktype {
    if (!lstat("$origdir/$fn")) {
        &unrepdiff2("nonexistent",$type{$fn});
    } else {
        $v= eval("$_[0] _ ? 2 : 1"); $v || &internerr("checktype $@ ($_[0])");
        return 1 if $v == 2;
        &unrepdiff2("something else",$type{$fn});
    }
    return 0;
}

sub setopmode {
    defined($opmode) && &usageerr("only one of -x or -b allowed, and only once");
    $opmode= $_[0];
}

sub unrepdiff {
    print(STDERR "$progname: cannot represent change to $fn: $_[0]\n")
        || &syserr("write syserr unrep");
    $ur++;
}

sub unrepdiff2 {
    print(STDERR "$progname: cannot represent change to $fn:\n".
          "$progname:  new version is $_[1]\n".
          "$progname:  old version is $_[0]\n")
        || &syserr("write syserr unrep");
    $ur++;
}

sub forkgzipwrite {
    open(GZIPFILE,"> $_[0]") || &syserr("create file $_[0]");
    pipe(GZIPREAD,GZIP) || &syserr("pipe for gzip");
    defined($cgz= fork) || &syserr("fork for gzip");
    if (!$cgz) {
        open(STDIN,"<&GZIPREAD") || &syserr("reopen gzip pipe"); close(GZIPREAD);
        close(GZIP); open(STDOUT,">&GZIPFILE") || &syserr("reopen tar.gz");
        exec('gzip','-9'); &syserr("exec gzip");
    }
    close(GZIPREAD);
    $gzipsigpipeok= 0;
}

sub forkgzipread {
    local $SIG{PIPE} = 'DEFAULT';
    open(GZIPFILE,"< $_[0]") || &syserr("read file $_[0]");
    pipe(GZIP,GZIPWRITE) || &syserr("pipe for gunzip");
    defined($cgz= fork) || &syserr("fork for gunzip");
    if (!$cgz) {
        open(STDOUT,">&GZIPWRITE") || &syserr("reopen gunzip pipe"); close(GZIPWRITE);
        close(GZIP); open(STDIN,"<&GZIPFILE") || &syserr("reopen input file");
        exec('gunzip'); &syserr("exec gunzip");
    }
    close(GZIPWRITE);
    $gzipsigpipeok= 1;
}

sub reapgzip {
    $cgz == waitpid($cgz,0) || &syserr("wait for gzip");
    !$? || ($gzipsigpipeok && WIFSIGNALED($?) && WTERMSIG($?)==SIGPIPE) ||
        subprocerr("gzip");
    close(GZIPFILE);
}

sub addfile {
    my ($filename)= @_;
    stat($filename) || &syserr("could not stat output file \`$filename'");
    $size= (stat _)[7];
    my $md5sum= `md5sum <$filename`;
    $? && &subprocerr("md5sum $filename");
    $md5sum =~ s/^([0-9a-f]{32})\s*-?\s*\n$/$1/ || &failure("md5sum gave bogus output \`$_'");
    $f{'Files'}.= "\n $md5sum $size $filename";
}

# replace \ddd with their corresponding character, refuse \ddd > \377
# modifies $_ (hs)
{
    my $backslash;
sub deoctify {
    my $fn= $_[0];
    $backslash= sprintf("\\%03o", unpack("C", "\\")) if !$backslash;

    s/\\{2}/$backslash/g;
    @_= split(/\\/, $fn);

    foreach (@_) {
        /^(\d{3})/ or next;
        &failure("bogus character `\\$1' in `$fn'\n") if oct($1) > 255;
        $_= pack("c", oct($1)) . $';
    }
    return join("", @_);
} }

