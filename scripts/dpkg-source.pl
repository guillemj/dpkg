#! /usr/bin/perl
# vim: set et sw=4 ts=8

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning warnerror error failure unknown
                           internerr syserr subprocerr usageerr info
                           $warnable_error $quiet_warnings);
use Dpkg::Arch qw(debarch_eq);
use Dpkg::Deps qw(@src_dep_fields %dep_field_type);
use Dpkg::Fields qw(:list capit);
use Dpkg::Compression;
use Dpkg::Control;
use Dpkg::Substvars;
use Dpkg::Version qw(check_version);
use Dpkg::Vars;
use Dpkg::Changelog qw(parse_changelog);
use Dpkg::Source::Compressor;
use Dpkg::Source::Package;

use POSIX;
use English;
use File::Spec;

textdomain("dpkg-dev");

my $varlistfile;
my $controlfile;
my $changelogfile;
my $changelogformat;

my $diff_ignore_default_regexp = '
# Ignore general backup files
(?:^|/).*~$|
# Ignore emacs recovery files
(?:^|/)\.#.*$|
# Ignore vi swap files
(?:^|/)\..*\.swp$|
# Ignore baz-style junk files or directories
(?:^|/),,.*(?:$|/.*$)|
# File-names that should be ignored (never directories)
(?:^|/)(?:DEADJOE|\.cvsignore|\.arch-inventory|\.bzrignore|\.gitignore)$|
# File or directory names that should be ignored
(?:^|/)(?:CVS|RCS|\.deps|\{arch\}|\.arch-ids|\.svn|\.hg|_darcs|\.git|
\.shelf|_MTN|\.bzr(?:\.backup|tags)?)(?:$|/.*$)
';
# Take out comments and newlines
$diff_ignore_default_regexp =~ s/^#.*$//mg;
$diff_ignore_default_regexp =~ s/\n//sg;

no warnings 'qw';
my @tar_ignore_default_pattern = qw(
*.a
*.la
*.o
*.so
*.swp
*~
,,*
.[#~]*
.arch-ids
.arch-inventory
.bzr
.bzr.backup
.bzr.tags
.bzrignore
.cvsignore
.deps
.git
.gitignore
.hg
.shelf
.svn
CVS
DEADJOE
RCS
_MTN
_darcs
{arch}
);

my @build_formats = ("1.0");
my %options = (
    # Compression related
    compression => 'gzip',
    comp_level => 9,
    comp_ext => $comp_ext{'gzip'},
    # Ignore files
    tar_ignore => [],
    diff_ignore_regexp => '',
    # Sourcestyle
    sourcestyle => 'X',
);

# Fields to remove/override
my %remove;
my %override;

my $substvars = Dpkg::Substvars->new();
my $opmode;
my $tar_ignore_default_pattern_done;

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_ = shift(@ARGV);
    if (m/^-b$/) {
        setopmode('build');
    } elsif (m/^-x$/) {
        setopmode('extract');
    } elsif (m/^--format=(.*)$/) {
        unshift @build_formats, $1;
    } elsif (m/^-Z/) {
	my $compression = $POSTMATCH;
	$options{'compression'} = $compression;
	$options{'comp_ext'} = $comp_ext{$compression};
	usageerr(_g("%s is not a supported compression"), $compression)
	    unless $comp_supported{$compression};
	Dpkg::Source::Compressor->set_default_compression($compression);
    } elsif (m/^-z/) {
	my $comp_level = $POSTMATCH;
	$options{'comp_level'} = $comp_level;
	usageerr(_g("%s is not a compression level"), $comp_level)
	    unless $comp_level =~ /^([1-9]|fast|best)$/;
	Dpkg::Source::Compressor->set_default_compression_level($comp_level);
    } elsif (m/^-s([akpursnAKPUR])$/) {
	warning(_g("-s%s option overrides earlier -s%s option"), $1,
		$options{'sourcestyle'}) if $options{'sourcestyle'} ne 'X';
        $options{'sourcestyle'} = $1;
    } elsif (m/^-c/) {
        $controlfile = $POSTMATCH;
    } elsif (m/^-l/) {
        $changelogfile = $POSTMATCH;
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat = $1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
        $override{$1} = $POSTMATCH;
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1} = 1;
    } elsif (m/^-i(.*)$/) {
        $options{'diff_ignore_regexp'} = $1 ? $1 : $diff_ignore_default_regexp;
    } elsif (m/^-I(.+)$/) {
        push @{$options{'tar_ignore'}}, $1;
    } elsif (m/^-I$/) {
        unless ($tar_ignore_default_pattern_done) {
            push @{$options{'tar_ignore'}}, @tar_ignore_default_pattern;
            # Prevent adding multiple times
            $tar_ignore_default_pattern_done = 1;
        }
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
        $substvars->set($1, $POSTMATCH);
    } elsif (m/^-T/) {
	$varlistfile = $POSTMATCH;
	warning(_g("substvars support is deprecated (see README.feature-removal-schedule)"));
    } elsif (m/^-(h|-help)$/) {
        usage();
        exit(0);
    } elsif (m/^--version$/) {
        version();
        exit(0);
    } elsif (m/^-W$/) {
        $warnable_error = 1;
    } elsif (m/^-E$/) {
        $warnable_error = 0;
    } elsif (m/^-q$/) {
        $quiet_warnings = 1;
    } elsif (m/^--$/) {
        last;
    } else {
        usageerr(_g("unknown option \`%s'"), $_);
    }
}

unless (defined($opmode)) {
    usageerr(_g("need -x or -b"));
}

if ($opmode eq 'build') {

    if (not scalar(@ARGV)) {
	usageerr(_g("-b needs a directory"));
    }
    my $dir = File::Spec->catdir(shift(@ARGV));
    stat($dir) || syserr(_g("cannot stat directory %s"), $dir);
    if (not -d $dir) {
	error(_g("directory argument %s is not a directory"), $dir);
    }
    $options{'ARGV'} = \@ARGV;

    $changelogfile ||= "$dir/debian/changelog";
    $controlfile ||= "$dir/debian/control";
    
    my %ch_options = (file => $changelogfile);
    $ch_options{"changelogformat"} = $changelogformat if $changelogformat;
    my $changelog = parse_changelog(%ch_options);
    my $control = Dpkg::Control->new($controlfile);

    my $srcpkg = Dpkg::Source::Package->new(options => \%options);
    my $fields = $srcpkg->{'fields'};

    my @sourcearch;
    my %archadded;
    my @binarypackages;

    # Scan control info of source package
    my $src_fields = $control->get_source();
    foreach $_ (keys %{$src_fields}) {
	my $v = $src_fields->{$_};
	if (m/^Source$/i) {
	    set_source_package($v);
	    $fields->{$_} = $v;
	} elsif (m/^(Format|Standards-Version|Origin|Maintainer|Homepage)$/i ||
		 m/^Dm-Upload-Allowed$/i ||
		 m/^Vcs-(Browser|Arch|Bzr|Cvs|Darcs|Git|Hg|Mtn|Svn)$/i) {
	    $fields->{$_} = $v;
	} elsif (m/^Uploaders$/i) {
	    ($fields->{$_} = $v) =~ s/[\r\n]//g; # Merge in a single-line
	} elsif (m/^Build-(Depends|Conflicts)(-Indep)?$/i) {
	    my $dep;
	    my $type = $dep_field_type{capit($_)};
	    $dep = Dpkg::Deps::parse($v, union =>  $type eq 'union');
	    error(_g("error occurred while parsing %s"), $_) unless defined $dep;
	    my $facts = Dpkg::Deps::KnownFacts->new();
	    $dep->simplify_deps($facts);
	    $dep->sort();
	    $fields->{$_} = $dep->dump();
	} elsif (s/^X[BC]*S[BC]*-//i) { # Include XS-* fields
	    $fields->{$_} = $v;
	} elsif (m/^$control_src_field_regex$/i || m/^X[BC]+-/i) {
	    # Silently ignore valid fields
	} else {
	    unknown(_g('general section of control info file'));
	}
    }

    # Scan control info of binary packages
    foreach my $pkg ($control->get_packages()) {
	my $p = $pkg->{'Package'};
	push(@binarypackages,$p);
	foreach $_ (keys %{$pkg}) {
	    my $v = $pkg->{$_};
            if (m/^Architecture$/) {
		if (debarch_eq($v, 'any')) {
                    @sourcearch= ('any');
		} elsif (debarch_eq($v, 'all')) {
                    if (!@sourcearch || $sourcearch[0] eq 'all') {
                        @sourcearch= ('all');
                    } else {
                        @sourcearch= ('any');
                    }
                } else {
		    if (@sourcearch && grep($sourcearch[0] eq $_, 'any', 'all')) {
			@sourcearch= ('any');
		    } else {
			for my $a (split(/\s+/, $v)) {
			    error(_g("`%s' is not a legal architecture string"),
			          $a)
				unless $a =~ /^[\w-]+$/;
			    error(_g("architecture %s only allowed on its " .
			             "own (list for package %s is `%s')"),
			          $a, $p, $a)
				if grep($a eq $_, 'any','all');
                            push(@sourcearch,$a) unless $archadded{$a}++;
                        }
                }
                }
                $fields->{'Architecture'}= join(' ',@sourcearch);
            } elsif (s/^X[BC]*S[BC]*-//i) { # Include XS-* fields
                $fields->{$_} = $v;
            } elsif (m/^$control_pkg_field_regex$/ ||
                     m/^X[BC]+-/i) { # Silently ignore valid fields
            } else {
                unknown(_g("package's section of control info file"));
            }
	}
    }

    # Scan fields of dpkg-parsechangelog
    foreach $_ (keys %{$changelog}) {
        my $v = $changelog->{$_};

	if (m/^Source$/) {
	    set_source_package($v);
	    $fields->{$_} = $v;
	} elsif (m/^Version$/) {
	    check_version($v);
	    $fields->{$_} = $v;
	} elsif (s/^X[BS]*C[BS]*-//i) {
	    $fields->{$_} = $v;
	} elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/i ||
		 m/^X[BS]+-/i) {
	} else {
	    unknown(_g("parsed version of changelog"));
	}
    }
    
    $fields->{'Binary'} = join(', ', @binarypackages);

    unshift @build_formats, $fields->{'Format'} if exists $fields->{'Format'};
    # Try all suggested formats until one is acceptable
    foreach my $format (@build_formats) {
        $fields->{'Format'} = $format;
        $srcpkg->upgrade_object_type(); # Fails if format is unsupported
        my ($res, $msg) = $srcpkg->can_build($dir);
        last if $res;
        info(_g("source format `%s' discarded: %s"), $format, $msg);
    }
    info(_g("using source format `%s'"), $fields->{'Format'});

    # Build the files (.tar.gz, .diff.gz, etc)
    $srcpkg->build($dir);

    # Write the .dsc
    my $dscname = $srcpkg->get_basename(1) . ".dsc";
    info(_g("building %s in %s"), $sourcepackage, $dscname);
    $substvars->parse($varlistfile) if $varlistfile && -e $varlistfile;
    $srcpkg->write_dsc(filename => $dscname,
		       remove => \%remove,
		       override => \%override,
		       substvars => $substvars);
    exit(0);

} elsif ($opmode eq 'extract') {

    # Check command line
    unless (scalar(@ARGV)) {
	usageerr(_g("-x needs at least one argument, the .dsc"));
    }
    if (scalar(@ARGV) > 2) {
	usageerr(_g("-x takes no more than two arguments"));
    }
    my $dsc = shift(@ARGV);
    if (-d $dsc) {
	usageerr(_g("-x needs the .dsc file as first argument, not a directory"));
    }

    # Create the object that does everything
    my $srcpkg = Dpkg::Source::Package->new(filename => $dsc,
					    options => \%options);

    # Decide where to unpack
    my $newdirectory = $srcpkg->get_basename();
    $newdirectory =~ s/_/-/g;
    if (@ARGV) {
	$newdirectory = File::Spec->catdir(shift(@ARGV));
	if (-e $newdirectory) {
	    error(_g("unpack target exists: %s"), $newdirectory);
	}
    }

    # Various checks before unpacking
    if ($srcpkg->is_signed()) {
	$srcpkg->check_signature();
    } else {
	warning(_g("extracting unsigned source package (%s)"), $dsc);
    }
    $srcpkg->check_checksums();

    # Unpack the source package (delegated to Dpkg::Source::Package::*)
    info(_g("extracting %s in %s"), $srcpkg->{'fields'}{'Source'}, $newdirectory);
    $srcpkg->extract($newdirectory);

    # Make sure debian/rules is executable
    my @s = lstat("$newdirectory/debian/rules");
    if (not scalar(@s)) {
	unless ($! == ENOENT) {
	    syserr(_g("cannot stat %s"), "$newdirectory/debian/rules");
	}
	warning(_g("%s does not exist"), "$newdirectory/debian/rules");
    } elsif (-f _) {
	chmod($s[2] | 0111, "$newdirectory/debian/rules") ||
	    syserr(_g("cannot make %s executable"), "$newdirectory/debian/rules");
    } else {
	warning(_g("%s is not a plain file"), "$newdirectory/debian/rules");
    }

    exit(0);
}

sub setopmode {
    if (defined($opmode)) {
	usageerr(_g("only one of -x or -b allowed, and only once"));
    }
    $opmode = $_[0];
}

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    print _g("
Copyright (C) 1996 Ian Jackson and Klee Dienes.
Copyright (C) 2008 Raphael Hertzog");

    print _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <command>

Commands:
  -x <filename>.dsc [<output-dir>]
                           extract source package.
  -b <dir> [<orig-dir>|<orig-targz>|\'\']
                           build source package.

Build options:
  -c<controlfile>          get control info from this file.
  -l<changelogfile>        get per-version info from this file.
  -F<changelogformat>      force change log format.
  -V<name>=<value>         set a substitution variable.
  -T<varlistfile>          read variables here, not debian/substvars.
  -D<field>=<value>        override or add a .dsc field and value.
  -U<field>                remove a field.
  -E                       turn certain warnings into errors.
  -W                       when -E is enabled, -W disables it.
  -q                       quiet operation, do not print warnings.
  -i[<regexp>]             filter out files to ignore diffs of
                             (defaults to: '%s').
  -I[<pattern>]            filter out files when building tarballs
                             (defaults to: %s).
  -sa                      auto select orig source (-sA is default).
  -sk                      use packed orig source (unpack & keep).
  -sp                      use packed orig source (unpack & remove).
  -su                      use unpacked orig source (pack & keep).
  -sr                      use unpacked orig source (pack & remove).
  -ss                      trust packed & unpacked orig src are same.
  -sn                      there is no diff, do main tarfile only.
  -sA,-sK,-sP,-sU,-sR      like -sa,-sk,-sp,-su,-sr but may overwrite.
  -Z<compression>          select compression to use (defaults to 'gzip',
                             supported are: %s).
  -z<level>                compression level to use (defaults to '9',
                             supported are: '1'-'9', 'best', 'fast')

Extract options:
  -sp (default)            leave orig source packed in current dir.
  -sn                      do not copy original source to current dir.
  -su                      unpack original source tree too.

General options:
  -h, --help               show this help message.
      --version            show the version.
"), $progname,
    $diff_ignore_default_regexp,
    join('', map { " -I$_" } @tar_ignore_default_pattern),
    "@comp_supported";
}

