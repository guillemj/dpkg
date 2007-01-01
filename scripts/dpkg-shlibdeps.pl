#! /usr/bin/perl
#
# dpkg-shlibdeps
# $Id: dpkg-shlibdeps.pl,v 1.19.2.2 2004/04/25 17:11:41 keybuk Exp $

my $dpkglibdir="/usr/lib/dpkg";
my $version="1.4.1.19"; # This line modified by Makefile

use English;
use POSIX qw(:errno_h :signal_h);

my $shlibsoverride= '/etc/dpkg/shlibs.override';
my $shlibsdefault= '/etc/dpkg/shlibs.default';
my $shlibslocal= 'debian/shlibs.local';
my $shlibsppdir= '/var/lib/dpkg/info';
my $shlibsppext= '.shlibs';
my $varnameprefix= 'shlibs';
my $dependencyfield= 'Depends';
my $varlistfile= 'debian/substvars';
my $packagetype= 'deb';

my @depfields= qw(Suggests Recommends Depends Pre-Depends);
my %depstrength;
my $i=0; grep($depstrength{$_}= ++$i, @depfields);

push(@INC,$dpkglibdir);
require 'controllib.pl';

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

#use strict;
#use warnings;

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman.
Copyright (C) 2006 Frank Lichtenheld.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <executable>|-e<executable> [<option> ...]

Positional options (order is significant):
  <executable>             include dependencies for <executable>,
  -e<executable>           (use -e if <executable> starts with \`-')
  -d<dependencyfield>      next executable(s) set shlibs:<dependencyfield>.

Options:
  -p<varnameprefix>        set <varnameprefix>:* instead of shlibs:*.
  -O                       print variable settings to stdout.
  -L<localshlibsfile>      shlibs override file, not debian/shlibs.local.
  -T<varlistfile>          update variables here, not debian/substvars.
  -t<type>                 set package type (default is deb).
  -h, --help               show this help message.
      --version            show the version.

Dependency fields recognised are:
  %s
"), $progname, join("/",@depfields);
}

my ($stdout, @exec, @execfield);
foreach (@ARGV) {
    if (m/^-T/) {
	$varlistfile= $POSTMATCH;
    } elsif (m/^-p(\w[-:0-9A-Za-z]*)$/) {
	$varnameprefix= $1;
    } elsif (m/^-L/) {
	$shlibslocal= $POSTMATCH;
    } elsif (m/^-O$/) {
	$stdout= 1;
    } elsif (m/^-(h|-help)$/) {
	usage; exit(0);
    } elsif (m/^--version$/) {
	version; exit(0);
    } elsif (m/^-d/) {
	$dependencyfield= capit($POSTMATCH);
	defined($depstrength{$dependencyfield}) ||
	    &warn(sprintf(_g("unrecognised dependency field \`%s'"), $dependencyfield));
    } elsif (m/^-e/) {
	push(@exec,$POSTMATCH); push(@execfield,$dependencyfield);
    } elsif (m/^-t/) {
	$packagetype= $POSTMATCH;
    } elsif (m/^-/) {
	usageerr(sprintf(_g("unknown option \`%s'"), $_));
    } else {
	push(@exec,$_); push(@execfield,$dependencyfield);
    }
}

@exec || usageerr(_g("need at least one executable"));

sub isbin {
    open (F, $_[0]) || die(sprintf(_g("unable to open '%s' for test"), $_[0]));
    my $d;
    if (read (F, $d, 4) != 4) {
       die (sprintf(_g("unable to read first four bytes of '%s' as magic number"), $_[0]));
    }
    if ($d =~ /^\177ELF$/) { # ELF binary
       return 1;
    } elsif (unpack ('N', $d) == 0x8086010B) { # obsd dyn bin
       return 1;
    } elsif (unpack ('N', $d) ==   0x86010B) { # obsd stat bin
       return 1;
    } elsif ($d =~ /^\#\!..$/) { # shell script
       return 0;
    } elsif (unpack ('N', $d) == 0xcafebabe) { # JAVA binary
       return 0;
    } else {
       die(sprintf(_g("unrecognized file type for '%s'"), $_[0]));
    }
}

my @librarypaths = qw( /lib /usr/lib /lib32 /usr/lib32 /lib64 /usr/lib64
		       /emul/ia32-linux/lib /emul/ia32-linux/usr/lib );
my %librarypaths = map { $_ => 'default' } @librarypaths;

if ($ENV{LD_LIBRARY_PATH}) {
    foreach (reverse split( /:/, $ENV{LD_LIBRARY_PATH} )) {
	s,/+$,,;
	unless (exists $librarypaths{$_}) {
	    $librarypaths{$_} = 'env';
	    unshift @librarypaths, $_;
	}
    }
}

# Support system library directories.
my $ldconfigdir = '/lib/ldconfig';
if (opendir(DIR, $ldconfigdir)) {
    my @dirents = readdir(DIR);
    closedir(DIR);

    for (@dirents) {
	next if /^\./;
	my $d = `readlink -f $ldconfigdir/$_`;
	chomp $d;
	unless (exists $librarypaths{$d}) {
	    $librarypaths{$d} = 'ldconfig';
	    push @librarypaths, $d;
	}
    }
}

open CONF, '</etc/ld.so.conf' or
    warn( sprintf(_g("couldn't open /etc/ld.so.conf: %s" ), $!));
while( <CONF> ) {
    next if /^\s*$/;
    chomp;
    s,/+$,,;
    unless (exists $librarypaths{$_}) {
	$librarypaths{$_} = 'conf';
	push @librarypaths, $_;
    }
}
close CONF;

my (%rpaths, %format);
my (@libfiles, @libname, @libsoname, @libfield, @libexec);
for ($i=0;$i<=$#exec;$i++) {
    if (!isbin ($exec[$i])) { next; }

    # Now we get the direct deps of the program
    defined(my $c= open(P,"-|")) || syserr(_g("cannot fork for objdump"));
    if (!$c) {
	exec("objdump","-p","--",$exec[$i]);
	syserr(_g("cannot exec objdump"));
    }
    while (<P>) {
	chomp;
	if (/^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
	    $format{$exec[$i]} = $1;
	} elsif (m,^\s*NEEDED\s+,) {
	    if (m,^\s*NEEDED\s+((\S+)\.so\.(\S+))$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libfield,$execfield[$i]);
		push(@libfiles,$1);
		push(@libexec,$exec[$i]);
	    } elsif (m,^\s*NEEDED\s+((\S+)-(\S+)\.so)$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libfield,$execfield[$i]);
		push(@libfiles,$1);
		push(@libexec,$exec[$i]);
	    } else {
		m,^\s*NEEDED\s+(\S+)$,;
		&warn(sprintf(_g("format of \`NEEDED %s' not recognized"), $1));
	    }
	} elsif (/^\s*RPATH\s+(\S+)\s*$/) {
	    push @{$rpaths{$exec[$i]}}, $1;
	}
    }
    close(P) or subprocerr(sprintf(_g("objdump on \`%s'"), $exec[$i]));
}

# Now: See if it is in this package.  See if it is in any other package.
my @curshlibs;
sub searchdir {
    my $dir = shift;
    if(opendir(DIR, $dir)) {
	my @dirents = readdir(DIR);
	closedir(DIR);
	for (@dirents) {
	    if ( -f "$dir/$_/DEBIAN/shlibs" ) {
		push(@curshlibs, "$dir/$_/DEBIAN/shlibs");
		next;
	    } elsif ( $_ !~ /^\./ && ! -e "$dir/$_/DEBIAN" &&
		      -d "$dir/$_" && ! -l "$dir/$_" ) {
		&searchdir("$dir/$_");
	    }
	}
    }
}

my $searchdir = $exec[0];
my $curpackdir = "debian/tmp";
do { $searchdir =~ s,/[^/]*$,,; } while($searchdir =~ m,/,
					&& ! -d "$searchdir/DEBIAN");
if ($searchdir =~ m,/,) {
    $curpackdir = $searchdir;
    $searchdir =~ s,/[^/]*,,;
    &searchdir($searchdir);
}

if (1 || $#curshlibs >= 0) {
  PRELIB:
    for ($i=0;$i<=$#libname;$i++) {
	if(scanshlibsfile($shlibslocal,$libname[$i],$libsoname[$i],$libfield[$i])
	   || scanshlibsfile($shlibsoverride,$libname[$i],$libsoname[$i],$libfield[$i])) {
	    splice(@libname, $i, 1);
	    splice(@libsoname, $i, 1);
	    splice(@libfield, $i, 1);
	    splice(@libfiles, $i, 1);
	    splice(@libexec, $i, 1);
	    $i--;
	    next PRELIB;
	}
	for my $shlibsfile (@curshlibs) {
	    if(scanshlibsfile($shlibsfile, $libname[$i], $libsoname[$i], $libfield[$i])) {
		splice(@libname, $i, 1);
		splice(@libsoname, $i, 1);
		splice(@libfield, $i, 1);
		splice(@libfiles, $i, 1);
		splice(@libexec, $i, 1);
		$i--;
		next PRELIB;
	    }
	}
    }
}

my %pathpackages;
if ($#libfiles >= 0) {
    grep(s/\[\?\*/\\$&/g, @libname);
    defined(my $c= open(P,"-|")) || syserr(_g("cannot fork for dpkg --search"));
    if (!$c) {
	close STDERR; # we don't need to see dpkg's errors
	open STDERR, "> /dev/null";
	$ENV{LC_ALL} = "C";
	exec("dpkg","--search","--",@libfiles);
	syserr(_g("cannot exec dpkg"));
    }
    while (<P>) {
	chomp;
	if (m/^local diversion |^diversion by/) {
	    &warn(_g("diversions involved - output may be incorrect"));
	    print(STDERR " $_\n") || syserr(_g("write diversion info to stderr"));
	} elsif (m=^(\S+(, \S+)*): (\S+)$=) {
	    push @{$pathpackages{$LAST_PAREN_MATCH}}, split(/, /, $1);
	} else {
	    &warn(sprintf(_g("unknown output from dpkg --search: \`%s'"), $_));
	}
    }
    close(P);
}

 LIB:
    for ($i=0;$i<=$#libname;$i++) {
	my $file = $libfiles[$i];
	my @packages;
	foreach my $rpath (@{$rpaths{$libexec[$i]}}) {
	    if (exists $pathpackages{"$rpath/$file"}
		&& format_matches($libexec[$i],"$rpath/$file")) {
		push @packages, @{$pathpackages{"$rpath/$file"}};
	    }
	}
	foreach my $path (@librarypaths) {
	    if (exists $pathpackages{"$path/$file"}
		&& format_matches($libexec[$i],"$path/$file")) {
		push @packages, @{$pathpackages{"$path/$file"}};
	    }
	}
	if (!@packages) {
	    &warn(sprintf(_g("could not find any packages for %s"), $libfiles[$i]));
	} else {
	    for my $p (@packages) {
		scanshlibsfile("$shlibsppdir/$p$shlibsppext",
			       $libname[$i],$libsoname[$i],$libfield[$i])
		    && next LIB;
	    }
	}
	scanshlibsfile($shlibsdefault,$libname[$i],$libsoname[$i],$libfield[$i])
	    && next;
	&warn(sprintf(_g("unable to find dependency information for ".
	                 "shared library %s (soname %s, ".
	                 "path %s, dependency field %s)"),
	              $libname[$i], $libsoname[$i],
	              $libfiles[$i], $libfield[$i]));
    }

sub format_matches {
    my ($file1, $file2) = @_;
    my ($format1, $format2) = (get_format($file1),get_format($file2));
    return $format1 eq $format2;
}

sub get_format {
    my ($file) = @_;

    if ($format{$file}) {
	return $format{$file};
    } else {
	defined(my $c= open(P,"-|")) || syserr(_g("cannot fork for objdump"));
	if (!$c) {
	    exec("objdump","-a","--",$file);
	    syserr(_g("cannot exec objdump"));
	}
	while (<P>) {
	    chomp;
	    if (/^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
		$format{$file} = $1;
		return $format{$file};
	    }
	}
	close(P) or subprocerr(sprintf(_g("objdump on \`%s'"), $file));
    }
}

my (%predefdepfdep, %unkdepfdone, %unkdepf);
sub scanshlibsfile {
    my ($fn,$ln,$lsn,$lf) = @_;
    my ($da,$dk);
    $fn= "./$fn" if $fn =~ m/^\s/;
    if (!open(SLF,"< $fn")) {
        $! == ENOENT || syserr(sprintf(_g("unable to open shared libs info file \`%s'"), $fn));
        return 0;
    }

    while (<SLF>) {
        s/\s*\n$//; next if m/^\#/;
        if (!m/^\s*(?:(\S+):\s+)?(\S+)\s+(\S+)/) {
            &warn(sprintf(_g("shared libs info file \`%s' line %d: bad line \`%s'"), $fn, $., $_));
            next;
        }
        next if defined $1 && $1 ne $packagetype;
        next if $2 ne $ln || $3 ne $lsn;
        return 1 if $fn eq "$curpackdir/DEBIAN/shlibs";
        $da= $POSTMATCH;
        last if defined $1; # exact match, otherwise keep looking
    }
    close(SLF);

    return 0 unless defined $da;

    for my $dv (split(/,/,$da)) {
        $dv =~ s/^\s+//; $dv =~ s/\s+$//;
        if (defined($depstrength{$lf})) {
            if (!defined($predefdepfdep{$dv}) ||
                $depstrength{$predefdepfdep{$dv}} < $depstrength{$lf}) {
                $predefdepfdep{$dv}= $lf;
            }
        } else {
            $dk= "$lf: $dv";
            if (!defined($unkdepfdone{$dk})) {
                $unkdepfdone{$dk}= 1;
                $unkdepf{$lf}.= ', ' if length($unkdepf{$lf});
                $unkdepf{$lf}.= $dv;
            }
        }
    }
    return 1;
}

my $fh;
if (!$stdout) {
    open(Y,"> $varlistfile.new") ||
        syserr(sprintf(_g("open new substvars file \`%s'"), "$varlistfile.new"));
    unless ($REAL_USER_ID) {
	chown(@fowner, "$varlistfile.new") ||
	    syserr(sprintf(_g("chown of \`%s'"), "$varlistfile.new"));
    }
    if (open(X,"< $varlistfile")) {
        while (<X>) {
            s/\n$//;
            next if m/^(\w[-:0-9A-Za-z]*):/ && $1 eq $varnameprefix;
            print(Y "$_\n") ||
                syserr(sprintf(_g("copy old entry to new varlist file \`%s'"), "$varlistfile.new"));
        }
    } elsif ($! != ENOENT) {
        syserr(sprintf(_g("open old varlist file \`%s' for reading"), $varlistfile));
    }
    $fh= 'Y';
} else {
    $fh= 'STDOUT';
}
my %defdepf;
for my $dv (sort keys %predefdepfdep) {
    my $lf= $predefdepfdep{$dv};
    $defdepf{$lf}.= ', ' if length($defdepf{$lf});
    $defdepf{$lf}.= $dv;
}
for my $lf (reverse @depfields) {
    next unless defined($defdepf{$lf});
    print($fh "$varnameprefix:$lf=$defdepf{$lf}\n")
        || syserr(_g("write output entry"));
}
for my $lf (sort keys %unkdepf) {
    print($fh "$varnameprefix:$lf=$unkdepf{$lf}\n")
        || syserr(_g("write userdef output entry"));
}
close($fh) || syserr(_g("close output"));
if (!$stdout) {
    rename("$varlistfile.new",$varlistfile) ||
        syserr(sprintf(_g("install new varlist file \`%s'"), $varlistfile));
}
