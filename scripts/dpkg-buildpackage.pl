#!/usr/bin/perl
#
# dpkg-buildpackage
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use Cwd;
use File::Basename;
use POSIX;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::BuildFlags;
use Dpkg::BuildOptions;
use Dpkg::BuildFeatures;
use Dpkg::Compression;
use Dpkg::Version;
use Dpkg::Changelog::Parse;
use Dpkg::Path qw(find_command);

textdomain("dpkg-dev");

sub showversion {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    print _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman
Copyright (C) 2007 Frank Lichtenheld");

    print _g("
This is free software; see the GNU General Public License version 2 or
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
  -T<target>     call debian/rules <target> with the proper environment
  --as-root      ensure -T calls the target with root rights
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
  -F             normal full build (binaries and sources).
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
  -Z<compressor> compression to use for source           }
  -nc            do not clean source tree (implies -b).
  -tc            clean source tree when finished.
  -ap            add pause before starting signature process.
  -i[<regex>]    ignore diffs of files matching regex.    } only passed
  -I[<pattern>]  filter out files when building tarballs. } to dpkg-source
  --source-option=<opt>
		 pass option <opt> to dpkg-source
  --changes-option=<opt>
		 pass option <opt> to dpkg-genchanges
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
     && find_command('gpg')) {
	 $signcommand = 'gpg';
} elsif (find_command('pgp')) {
	$signcommand = 'pgp'
}

my ($admindir, $signkey, $forcesigninterface, $usepause, $noclean,
    $cleansource, $since, $maint,
    $changedby, $desc, $parallel);
my $checkbuilddep = 1;
my $signsource = 1;
my $signchanges = 1;
my $binarytarget = 'binary';
my $buildtarget = 'build';
my $targetarch = my $targetgnusystem = '';
my $call_target = '';
my $call_target_as_root = 0;
my (@checkbuilddep_opts, @changes_opts, @source_opts);

use constant BUILD_DEFAULT    => 1;
use constant BUILD_SOURCE     => 2;
use constant BUILD_ARCH_DEP   => 4;
use constant BUILD_ARCH_INDEP => 8;
use constant BUILD_BINARY     => BUILD_ARCH_DEP | BUILD_ARCH_INDEP;
use constant BUILD_ALL        => BUILD_BINARY | BUILD_SOURCE;
my $include = BUILD_ALL | BUILD_DEFAULT;

sub build_normal() { return ($include & BUILD_ALL) == BUILD_ALL; }
sub build_sourceonly() { return $include == BUILD_SOURCE; }
sub build_binaryonly() { return !($include & BUILD_SOURCE); }
sub build_opt() {
    return (($include == BUILD_BINARY) ? '-b' :
            (($include == BUILD_ARCH_DEP) ? '-B' :
             (($include == BUILD_ARCH_INDEP) ? '-A' :
              (($include == BUILD_SOURCE) ? '-S' :
               internerr("build_opt called with include=$include")))));
}

while (@ARGV) {
    $_ = shift @ARGV;

    if (/^(--help|-h)$/) {
	usage;
	exit 0;
    } elsif (/^--version$/) {
	showversion;
	exit 0;
    } elsif (/^--admindir$/) {
        $admindir = shift @ARGV;
    } elsif (/^--admindir=(.*)$/) {
	$admindir = $1;
    } elsif (/^--source-option=(.*)$/) {
	push @source_opts, $1;
    } elsif (/^--changes-option=(.*)$/) {
	push @changes_opts, $1;
    } elsif (/^-j(\d*)$/) {
	$parallel = $1 || '';
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
	push @changes_opts, $_;
    } elsif (/^-(?:s[insAkurKUR]|[zZ].*|i.*|I.*)$/) {
	push @source_opts, $_; # passed to dpkg-source
    } elsif (/^-tc$/) {
	$cleansource = 1;
    } elsif (/^-t(.*)$/) {
	$targetgnusystem = $1; # Order DOES matter!
    } elsif (/^(--target|-T)$/) {
        $call_target = shift @ARGV;
    } elsif (/^(--target=|-T)(.+)$/) {
        $call_target = $2;
    } elsif (/^--as-root$/) {
        $call_target_as_root = 1;
    } elsif (/^-nc$/) {
	$noclean = 1;
    } elsif (/^-b$/) {
	build_sourceonly && usageerr(_g("cannot combine %s and %s"), $_, "-S");
	$include = BUILD_BINARY;
	push @changes_opts, '-b';
	@checkbuilddep_opts = ();
	$buildtarget = 'build';
	$binarytarget = 'binary';
    } elsif (/^-B$/) {
	build_sourceonly && usageerr(_g("cannot combine %s and %s"), $_, "-S");
	$include = BUILD_ARCH_DEP;
	push @changes_opts, '-B';
	@checkbuilddep_opts = ('-B');
	$buildtarget = 'build-arch';
	$binarytarget = 'binary-arch';
    } elsif (/^-A$/) {
	build_sourceonly && usageerr(_g("cannot combine %s and %s"), $_, "-S");
	$include = BUILD_ARCH_INDEP;
	push @changes_opts, '-A';
	@checkbuilddep_opts = ();
	$buildtarget = 'build-indep';
	$binarytarget = 'binary-indep';
    } elsif (/^-S$/) {
	build_binaryonly && usageerr(_g("cannot combine %s and %s"), build_opt, "-S");
	$include = BUILD_SOURCE;
	push @changes_opts, '-S';
	@checkbuilddep_opts = ('-B');
    } elsif (/^-F$/) {
	!build_normal && usageerr(_g("cannot combine %s and %s"), $_, build_opt);
	$include = BUILD_ALL;
	@checkbuilddep_opts = ();
    } elsif (/^-v(.*)$/) {
	$since = $1;
    } elsif (/^-m(.*)$/) {
	$maint = $1;
    } elsif (/^-e(.*)$/) {
	$changedby = $1;
    } elsif (/^-C(.*)$/) {
	$desc = $1;
    } elsif (m/^-[EW]$/) {
	# Deprecated option
	warning(_g("-E and -W are deprecated, they are without effect"));
    } elsif (/^-R(.*)$/) {
	@debian_rules = split /\s+/, $1;
    } else {
	usageerr(_g("unknown option or argument %s"), $_);
    }
}

if ($noclean) {
    # -nc without -b/-B/-A/-S/-F implies -b
    $include = BUILD_BINARY if ($include & BUILD_DEFAULT);
}

my $buildfeats = Dpkg::BuildFeatures->new();
$buildtarget = 'build' unless $buildfeats->has('build-arch');

if ($< == 0) {
    warning(_g("using a gain-root-command while being root")) if (@rootcommand);
} else {
    push @rootcommand, "fakeroot" unless @rootcommand;

    if (!find_command($rootcommand[0])) {
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

my $build_opts = Dpkg::BuildOptions->new();
if (defined $parallel) {
    $parallel = $build_opts->get("parallel") if $build_opts->has("parallel");
    $ENV{MAKEFLAGS} ||= '';
    $ENV{MAKEFLAGS} .= " -j$parallel";
    $build_opts->set("parallel", $parallel);
    $build_opts->export();
}

my $build_flags = Dpkg::BuildFlags->new();
$build_flags->load_config();
foreach my $flag ($build_flags->list()) {
    $ENV{$flag} = $build_flags->get($flag);
    printf(_g("%s: export %s from dpkg-buildflags (origin: %s): %s\n"),
	   $progname, $flag, $build_flags->get_origin($flag), $ENV{$flag});
}

my $cwd = cwd();
my $dir = basename($cwd);

my $changelog = changelog_parse();

my $pkg = mustsetvar($changelog->{source}, _g('source package'));
my $version = mustsetvar($changelog->{version}, _g('source version'));
my ($ok, $error) = version_check($version);
error($error) unless $ok;

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

my $arch;
unless (build_sourceonly) {
    $arch = mustsetvar($ENV{'DEB_HOST_ARCH'}, _g('host architecture'));
} else {
    $arch = 'source';
}

# Preparation of environment stops here

(my $sversion = $version) =~ s/^\d+://;

my $pv = "${pkg}_$sversion";
my $pva = "${pkg}_${sversion}_$arch";

if (not -x "debian/rules") {
    warning(_g("debian/rules is not executable: fixing that."));
    chmod(0755, "debian/rules"); # No checks of failures, non fatal
}

unless ($call_target) {
    chdir('..') or syserr('chdir ..');
    withecho('dpkg-source', @source_opts, '--before-build', $dir);
    chdir($dir) or syserr("chdir $dir");
}

if ($checkbuilddep) {
    if ($admindir) {
	push @checkbuilddep_opts, "--admindir=$admindir";
    }

    system('dpkg-checkbuilddeps', @checkbuilddep_opts);
    if (not WIFEXITED($?)) {
        subprocerr('dpkg-checkbuilddeps');
    } elsif (WEXITSTATUS($?)) {
	warning(_g("Build dependencies/conflicts unsatisfied; aborting."));
	warning(_g("(Use -d flag to override.)"));

	if (build_sourceonly) {
	    warning(_g("This is currently a non-fatal warning with -S, but"));
	    warning(_g("will probably become fatal in the future."));
	} else {
	    exit 3;
	}
    }
}

if ($call_target) {
    if ($call_target_as_root or
        $call_target =~ /^(clean|binary(|-arch|-indep))$/)
    {
        withecho(@rootcommand, @debian_rules, $call_target);
    } else {
        withecho(@debian_rules, $call_target);
    }
    exit 0;
}

unless ($noclean) {
    withecho(@rootcommand, @debian_rules, 'clean');
}
unless (build_binaryonly) {
    warning(_g("it is a bad idea to generate a source package " .
               "without cleaning up first, it might contain undesired " .
               "files.")) if $noclean;
    chdir('..') or syserr('chdir ..');
    withecho('dpkg-source', @source_opts, '-b', $dir);
    chdir($dir) or syserr("chdir $dir");
}
unless (build_sourceonly) {
    withecho(@debian_rules, $buildtarget);
    withecho(@rootcommand, @debian_rules, $binarytarget);
}
if ($usepause &&
    ($signchanges || (!build_binaryonly && $signsource))) {
    print _g("Press the return key to start signing process\n");
    getc();
}

my $signerrors;
unless (build_binaryonly) {
    if ($signsource && signfile("$pv.dsc")) {
	$signerrors = _g("Failed to sign .dsc and .changes file");
	$signchanges = 0;
    }
}

if (defined($maint)) { push @changes_opts, "-m$maint" }
if (defined($changedby)) { push @changes_opts, "-e$changedby" }
if (defined($since)) { push @changes_opts, "-v$since" }
if (defined($desc)) { push @changes_opts, "-C$desc" }

my $chg = "../$pva.changes";
print STDERR " dpkg-genchanges @changes_opts >$chg\n";
open CHANGES, '-|', 'dpkg-genchanges', @changes_opts
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
my $ext = $compression_re_file_ext;
if (fileomitted '\.deb') {
    # source only upload
    if (fileomitted "\.diff\.$ext" and fileomitted "\.debian\.tar\.$ext") {
	$srcmsg = _g('source only upload: Debian-native package');
    } elsif (fileomitted "\.orig\.tar\.$ext") {
	$srcmsg = _g('source only, diff-only upload (original source NOT included)');
    } else {
	$srcmsg = _g('source only upload (original source is included)');
    }
} else {
    $srcmsg = _g('full upload (original source is included)');
    if (fileomitted '\.dsc') {
	$srcmsg = _g('binary only upload (no source included)');
    } elsif (fileomitted "\.diff\.$ext" and fileomitted "\.debian\.tar\.$ext") {
	$srcmsg = _g('full upload; Debian-native package (full source is included)');
    } elsif (fileomitted "\.orig\.tar\.$ext") {
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
chdir('..') or syserr('chdir ..');
withecho('dpkg-source', @source_opts, '--after-build', $dir);
chdir($dir) or syserr("chdir $dir");

print "$progname: $srcmsg\n";
if ($signerrors) {
    warning($signerrors);
    exit 1;
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
