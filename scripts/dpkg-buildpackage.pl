#!/usr/bin/perl

use strict;
use warnings;

use Cwd;
use File::Basename;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error failure syserr subprocerr usageerr
                           $warnable_error);
use Dpkg::BuildOptions;
use Dpkg::Compression;
use Dpkg::Version qw(check_version);
use Dpkg::Changelog qw(parse_changelog);
use Dpkg::Arch qw(get_build_arch debarch_to_gnutriplet);

textdomain("dpkg-dev");

sub showversion {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    print _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman
Copyright (C) 2007 Frank Lichtenheld");

    print _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
	printf _g("
Usage: %s [<options> ...]

Options:
  -r<gain-root-command>
                 command to gain root privileges (default is fakeroot).
  -R<rules>      rules file to execute (default is debian/rules).
  -p<sign-command>
  -d             do not check build dependencies and conflicts.
  -D             check build dependencies and conflicts.
  -j[<number>]   specify jobs to run simultaneously } passed to debian/rules
  -k<keyid>      the key to use for signing.
  -sgpg          the sign-command is called like GPG.
  -spgp          the sign-command is called like PGP.
  -us            unsigned source.
  -uc            unsigned changes.
  -a<arch>       Debian architecture we build for (implies -d).
  -b             binary-only, do not build source.   } also passed to
  -B             binary-only, no arch-indep files.   } dpkg-genchanges
  -A             binary-only, only arch-indep files. }
  -S             source only, no binary files.     }
  -t<system>     set GNU system type.           } passed to dpkg-architecture
  -v<version>    changes since version <version>.      }
  -m<maint>      maintainer for package is <maint>.    }
  -e<maint>      maintainer for release is <maint>.    } only passed
  -C<descfile>   changes are described in <descfile>.  } to dpkg-genchanges
  -si (default)  src includes orig if new upstream.    }
  -sa            uploaded src always includes orig.    }
  -sd            uploaded src is diff and .dsc only.   }
  -sn            force Debian native source format.      }
  -s[sAkurKUR]   see dpkg-source for explanation.        } only passed
  -z<level>      compression level of source             } to dpkg-source
  -Z(gz|bz2|lzma) compression to use for source          }
  -nc            do not clean source tree (implies -b).
  -tc            clean source tree when finished.
  -ap            add pause before starting signature process.
  -E             turn certain warnings into errors.       } passed to
  -W             when -E is turned on, -W turns it off.   } dpkg-source
  -i[<regex>]    ignore diffs of files matching regex.    } only passed
  -I[<pattern>]  filter out files when building tarballs. } to dpkg-source
  --admindir=<directory>
                 change the administrative directory.
  -h, --help     show this help message.
      --version  show the version.
"), $progname;
}

my @debian_rules = ("debian/rules");
my @rootcommand = ();
my $signcommand = '';
if ( ( ($ENV{GNUPGHOME} && -e $ENV{GNUPGHOME})
       || ($ENV{HOME} && -e "$ENV{HOME}/.gnupg") )
     && testcommand('gpg')) {
	 $signcommand = 'gpg';
} elsif (testcommand('pgp')) {
	$signcommand = 'pgp'
}

my ($admindir, $signkey, $forcesigninterface, $usepause, $noclean,
    $sourcestyle, $cleansource,
    $binaryonly, $sourceonly, $since, $maint,
    $changedby, $desc, $parallel);
my (@checkbuilddep_args, @passopts, @tarignore);
my $checkbuilddep = 1;
my $signsource = 1;
my $signchanges = 1;
my $diffignore = '';
my $binarytarget = 'binary';
my $targetarch = my $targetgnusystem = '';

while (@ARGV) {
    $_ = shift @ARGV;

    if (/^(--help|-h)$/) {
	usage;
	exit 0;
    } elsif (/^--version$/) {
	showversion;
	exit 0;
    } elsif (/^--admindir=(.*)$/) {
	$admindir = $1;
    } elsif (/^-j(\d*)$/) {
	$parallel = $1 || '-1';
    } elsif (/^-r(.*)$/) {
	@rootcommand = split /\s+/, $1;
    } elsif (/^-p(.*)$/) {
	$signcommand = $1;
    } elsif (/^-k(.*)$/) {
	$signkey = $1;
    } elsif (/^-([dD])$/) {
	$checkbuilddep = ($1 eq 'D');
    } elsif (/^-s(gpg|pgp)$/) {
	$forcesigninterface = $1;
    } elsif (/^-us$/) {
	$signsource = 0;
    } elsif (/^-uc$/) {
	$signchanges = 0;
    } elsif (/^-ap$/) {
	$usepause = 1;
    } elsif (/^-a(.*)$/) {
	$targetarch = $1;
	$checkbuilddep = 0;
    } elsif (/^-s[iad]$/) {
	$sourcestyle = $_;
    } elsif (/^-s[nsAkurKUR]$/) {
	push @passopts, $_; # passed to dpkg-source
    } elsif (/^-[zZ]/) {
	push @passopts, $_; # passed to dpkg-source
    } elsif (/^-i.*$/) {
	$diffignore = $_;
    } elsif (/^-I.*$/) {
	push @tarignore, $_;
    } elsif (/^-tc$/) {
	$cleansource = 1;
    } elsif (/^-t(.*)$/) {
	$targetgnusystem = $1; # Order DOES matter!
    } elsif (/^-nc$/) {
	$noclean = 1;
	if ($sourceonly) {
	    usageerr(_g("cannot combine %s and %s"), '-nc', '-S');
	}
	unless ($binaryonly) {
	    $binaryonly = '-b';
	}
    } elsif (/^-b$/) {
	$binaryonly = '-b';
	@checkbuilddep_args = ();
	$binarytarget = 'binary';
	if ($sourceonly) {
	    usageerr(_g("cannot combine %s and %s"), '-b', '-S');
	}
    } elsif (/^-B$/) {
	$binaryonly = '-B';
	@checkbuilddep_args = ('-B');
	$binarytarget = 'binary-arch';
	if ($sourceonly) {
	    usageerr(_g("cannot combine %s and %s"), '-B', '-S');
	}
    } elsif (/^-A$/) {
	$binaryonly = '-A';
	@checkbuilddep_args = ();
	$binarytarget = 'binary-indep';
	if ($sourceonly) {
	    usageerr(_g("cannot combine %s and %s"), '-A', '-S');
	}
    } elsif (/^-S$/) {
	$sourceonly = '-S';
	@checkbuilddep_args = ('-B');
	if ($binaryonly) {
	    usageerr(_g("cannot combine %s and %s"), $binaryonly, '-S');
	}
    } elsif (/^-v(.*)$/) {
	$since = $1;
    } elsif (/^-m(.*)$/) {
	$maint = $1;
    } elsif (/^-e(.*)$/) {
	$changedby = $1;
    } elsif (/^-C(.*)$/) {
	$desc = $1;
    } elsif (/^-W$/) {
	$warnable_error = 1;
	push @passopts, '-W';
    } elsif (/^-E$/) {
	$warnable_error = 0;
	push @passopts, '-E';
    } elsif (/^-R(.*)$/) {
	@debian_rules = split /\s+/, $1;
    } else {
	usageerr(_g("unknown option or argument %s"), $_);
    }
}

if ($< == 0) {
    warning(_g("using a gain-root-command while being root")) if (@rootcommand);
} else {
    push @rootcommand, "fakeroot" unless @rootcommand;

    if (!testcommand($rootcommand[0])) {
	if ($rootcommand[0] eq 'fakeroot') {
	    error(_g("fakeroot not found, either install the fakeroot\n" .
	             "package, specify a command with the -r option, " .
	             "or run this as root"));
	} else {
	    error(_g("gain-root-commmand '%s' not found"), $rootcommand[0]);
	}
    }
}

unless ($signcommand) {
    $signsource = 0;
    $signchanges = 0;
}

my $signinterface;
if ($forcesigninterface) {
    $signinterface = $forcesigninterface;
} else {
    $signinterface = $signcommand;
}

if ($signcommand) {
    if ($signinterface !~ /^(gpg|pgp)$/) {
	warning(_g("unknown sign command, assuming pgp style interface"));
    } elsif ($signinterface eq 'pgp') {
	if ($signsource or $signchanges) {
	    warning(_g("PGP support is deprecated (see README.feature-removal-schedule)"));
	}
    }
}

my $build_opts = Dpkg::BuildOptions::parse();
if ($parallel) {
    $parallel = $build_opts->{parallel} if (defined $build_opts->{parallel});
    $ENV{MAKEFLAGS} ||= '';
    if ($parallel eq '-1') {
	$ENV{MAKEFLAGS} .= " -j";
    } else {
	$ENV{MAKEFLAGS} .= " -j$parallel";
    }
    $build_opts->{parallel} = $parallel;
    Dpkg::BuildOptions::set($build_opts);
}

my $default_flags = defined $build_opts->{noopt} ? "-g -O0" : "-g -O2";
my %flags = ( CPPFLAGS => '',
	      CFLAGS   => $default_flags,
	      CXXFLAGS => $default_flags,
	      FFLAGS   => $default_flags,
	      LDFLAGS  => '',
    );

foreach my $flag (keys %flags) {
    if ($ENV{$flag}) {
	printf(_g("%s: use %s from environment: %s\n"), $progname,
		  $flag, $ENV{$flag});
    } else {
	$ENV{$flag} = $flags{$flag};
	printf(_g("%s: set %s to default value: %s\n"), $progname,
		  $flag, $ENV{$flag});
    }
    if ($ENV{"${flag}_APPEND"}) {
	$ENV{$flag} .= " ".$ENV{"${flag}_APPEND"};
    }
}

my $cwd = cwd();
my $dir = basename($cwd);

my $changelog = parse_changelog();

my $pkg = mustsetvar($changelog->{source}, _g('source package'));
my $version = mustsetvar($changelog->{version}, _g('source version'));
check_version($version);

my $maintainer;
if ($changedby) {
    $maintainer = $changedby;
} elsif ($maint) {
    $maintainer = $maint;
} else {
    $maintainer = mustsetvar($changelog->{maintainer}, _g('source changed by'));
}

open my $arch_env, '-|', 'dpkg-architecture', "-a$targetarch",
    "-t$targetgnusystem", '-s', '-f' or subprocerr('dpkg-architecture');
while ($_ = <$arch_env>) {
    chomp;
    my @cmds = split /\s*;\s*/;
    foreach (@cmds) {
	/^\s*(\w+)=([\w-]*)\s*$/ && do {
	    $ENV{$1} = $2;
	};
    }
}
close $arch_env or subprocerr('dpkg-architecture');

# In case of cross-compilation, give sensible default search path
# for some widely used tools
$targetgnusystem = debarch_to_gnutriplet($targetarch) if $targetarch;
if ($targetgnusystem and
    ($targetgnusystem ne debarch_to_gnutriplet(get_build_arch())))
{
   $ENV{PKG_CONFIG_LIBDIR} ||= "/usr/$targetgnusystem/lib/pkgconfig/:" .
                               "/usr/share/pkgconfig/";
}

my $arch;
unless ($sourceonly) {
    $arch = mustsetvar($ENV{'DEB_HOST_ARCH'}, _g('host architecture'));
} else {
    $arch = 'source';
}

(my $sversion = $version) =~ s/^\d+://;

my $pv = "${pkg}_$sversion";
my $pva = "${pkg}_${sversion}_$arch";

if ($checkbuilddep) {
    if ($admindir) {
	push @checkbuilddep_args, "--admindir=$admindir";
    }

    if (system('dpkg-checkbuilddeps', @checkbuilddep_args)) {
	warning(_g("Build dependencies/conflicts unsatisfied; aborting."));
	warning(_g("(Use -d flag to override.)"));

	if ($sourceonly) {
	    warning(_g("This is currently a non-fatal warning with -S, but"));
	    warning(_g("will probably become fatal in the future."));
	} else {
	    exit 3;
	}
    }
}

unless ($noclean) {
    withecho(@rootcommand, @debian_rules, 'clean');
}
unless ($binaryonly) {
    chdir('..') or failure('chdir ..');
    my @opts = @passopts;
    if ($diffignore) { push @opts, $diffignore }
    push @opts, @tarignore;
    withecho('dpkg-source', @opts, '-b', $dir);
    chdir($dir) or failure("chdir $dir");
}
unless ($sourceonly) {
    withecho(@debian_rules, 'build');
    withecho(@rootcommand, @debian_rules, $binarytarget);
}
if ($usepause &&
    ($signchanges || ( !$binaryonly && $signsource )) ) {
    print _g("Press the return key to start signing process\n");
    getc();
}

my $signerrors;
unless ($binaryonly) {
    if ($signsource && signfile("$pv.dsc")) {
	$signerrors = _g("Failed to sign .dsc and .changes file");
	$signchanges = 0;
    }
}

my @change_opts;

if ($binaryonly) { push @change_opts, $binaryonly }
if ($sourceonly) { push @change_opts, $sourceonly }
if ($sourcestyle) { push @change_opts, $sourcestyle }

if ($maint) { push @change_opts, "-m$maint" }
if ($changedby) { push @change_opts, "-e$changedby" }
if ($since) { push @change_opts, "-v$since" }
if ($desc) { push @change_opts, "-C$desc" }

my $chg = "../$pva.changes";
print STDERR " dpkg-genchanges @change_opts >$chg\n";
open CHANGES, '-|', 'dpkg-genchanges', @change_opts
    or subprocerr('dpkg-genchanges');

open OUT, '>', $chg or syserr(_g('write changes file'));

my $infiles = my $files = '';
while ($_ = <CHANGES>) {
    print OUT $_ or syserr(_g('write changes file'));
    chomp;

    if (/^Files:/i) {
	$infiles = 1;
    } elsif ($infiles && /^\s+(.*)$/) {
	$files .= " $1 ";
    } elsif ($infiles && /^\S/) {
	$infiles = 0;
    }
}

close CHANGES or subprocerr(_g('dpkg-genchanges'));
close OUT or syserr(_g('write changes file'));

my $srcmsg;
sub fileomitted($) { return $files !~ /$_[0]/ }
if (fileomitted '\.deb') {
    # source only upload
    if (fileomitted "\.diff\.$comp_regex" and fileomitted "\.debian\.tar\.$comp_regex") {
	$srcmsg = _g('source only upload: Debian-native package');
    } elsif (fileomitted "\.orig\.tar\.$comp_regex") {
	$srcmsg = _g('source only, diff-only upload (original source NOT included)');
    } else {
	$srcmsg = _g('source only upload (original source is included)');
    }
} else {
    $srcmsg = _g('full upload (original source is included)');
    if (fileomitted '\.dsc') {
	$srcmsg = _g('binary only upload (no source included)');
    } elsif (fileomitted "\.diff\.$comp_regex" and fileomitted "\.debian\.tar\.$comp_regex") {
	$srcmsg = _g('full upload; Debian-native package (full source is included)');
    } elsif (fileomitted "\.orig\.tar\.$comp_regex") {
	$srcmsg = _g('binary and diff upload (original source NOT included)');
    } else {
	$srcmsg = _g('full upload (original source is included)');
    }
}

if ($signchanges && signfile("$pva.changes")) {
    $signerrors = _g("Failed to sign .changes file");
}

if ($cleansource) {
    withecho(@rootcommand, @debian_rules, 'clean');
}

print "$progname: $srcmsg\n";
if ($signerrors) {
    warning($signerrors);
    exit 1;
}

sub testcommand {
    my ($cmd) = @_;

    my $fullcmd = `which $cmd`;
    chomp $fullcmd;
    return $fullcmd && -x $fullcmd;
}

sub mustsetvar {
    my ($var, $text) = @_;

    error(_g("unable to determine %s"), $text)
	unless defined($var);

    print "$progname: $text $var\n";
    return $var;
}

sub withecho {
    shift while !$_[0];
    print STDERR " @_\n";
    system(@_)
	and subprocerr("@_");
}

sub signfile {
    my ($file) = @_;
    print STDERR " signfile $file\n";
    my $qfile = quotemeta($file);

    if ($signinterface eq 'gpg') {
	system("(cat ../$qfile ; echo '') | ".
	       "$signcommand --utf8-strings --local-user "
	       .quotemeta($signkey||$maintainer).
	       " --clearsign --armor --textmode  > ../$qfile.asc");
    } else {
	system("$signcommand -u ".quotemeta($signkey||$maintainer).
	       " +clearsig=on -fast <../$qfile >../$qfile.asc");
    }
    my $status = $?;
    unless ($status) {
	system('mv', '--', "../$file.asc", "../$file")
	    and subprocerr('mv');
    } else {
	system('rm', '-f', "../$file.asc")
	    and subprocerr('rm -f');
    }
    print "\n";
    return $status
}
