#!/usr/bin/perl

use warnings;
use strict;

use IO::Handle;
use IO::File;
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control;
use Dpkg::Version qw(compare_versions);
use Dpkg::Checksums;
use Dpkg::Source::CompressedFile;

textdomain("dpkg-dev");

# Do not pollute STDOUT with info messages
report_options(info_fh => \*STDERR);

my (@samemaint, @changedmaint);
my @spuriousover;
my %packages;
my %overridden;

use Getopt::Long qw(:config bundling);

my %options = (help            => sub { usage(); exit 0; },
	       version         => \&version,
	       type            => undef,
	       udeb            => \&set_type_udeb,
	       arch            => undef,
	       multiversion    => 0,
	       'extra-override'=> undef,
               medium          => undef,
	      );

my $result = GetOptions(\%options,
                        'help|h|?', 'version', 'type|t=s', 'udeb|u!',
                        'arch|a=s', 'multiversion|m!', 'extra-override|e=s',
                        'medium|M=s');

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;
    exit;
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <binarypath> [<overridefile> [<pathprefix>]] > Packages

Options:
  -t, --type <type>        scan for <type> packages (default is 'deb').
  -u, --udeb               scan for udebs (obsolete alias for -tudeb).
  -a, --arch <arch>        architecture to scan for.
  -m, --multiversion       allow multiple versions of a single package.
  -e, --extra-override <file>
                           use extra override file.
  -M, --medium <medium>    add X-Medium field for dselect multicd access method
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}

sub set_type_udeb()
{
    warning(_g("-u, --udeb option is deprecated (see README.feature-removal-schedule)"));
    $options{type} = 'udeb';
}

sub load_override
{
    my $override = shift;
    my $comp_file = Dpkg::Source::CompressedFile->new(filename => $override);
    my $override_fh = $comp_file->open_for_read();

    while (<$override_fh>) {
	s/\#.*//;
	s/\s+$//;
	next unless $_;

	my ($p, $priority, $section, $maintainer) = split(/\s+/, $_, 4);

	if (not defined($packages{$p})) {
	    push(@spuriousover, $p);
	    next;
	}

	for my $package (@{$packages{$p}}) {
	    if ($maintainer) {
		if ($maintainer =~ m/(.+?)\s*=\>\s*(.+)/) {
		    my $oldmaint = $1;
		    my $newmaint = $2;
		    my $debmaint = $$package{Maintainer};
		    if (!grep($debmaint eq $_, split(m:\s*//\s*:, $oldmaint))) {
			push(@changedmaint,
			     sprintf(_g("  %s (package says %s, not %s)"),
			             $p, $$package{Maintainer}, $oldmaint));
		    } else {
			$$package{Maintainer} = $newmaint;
		    }
		} elsif ($$package{Maintainer} eq $maintainer) {
		    push(@samemaint, "  $p ($maintainer)");
		} else {
		    warning(_g("Unconditional maintainer override for %s"), $p);
		    $$package{Maintainer} = $maintainer;
		}
	    }
	    $$package{Priority} = $priority;
	    $$package{Section} = $section;
	}
	$overridden{$p} = 1;
    }

    close($override_fh);
    $comp_file->cleanup_after_open();
}

sub load_override_extra
{
    my $extra_override = shift;
    my $comp_file = Dpkg::Source::CompressedFile->new(filename => $extra_override);
    my $override_fh = $comp_file->open_for_read();

    while (<$override_fh>) {
	s/\#.*//;
	s/\s+$//;
	next unless $_;

	my ($p, $field, $value) = split(/\s+/, $_, 3);

	next unless defined($packages{$p});

	for my $package (@{$packages{$p}}) {
	    $$package{$field} = $value;
	}
    }

    close($override_fh);
    $comp_file->cleanup_after_open();
}

usage() and exit 1 if not $result;

if (not @ARGV >= 1 && @ARGV <= 3) {
    usageerr(_g("1 to 3 args expected"));
}

my $type = defined($options{type}) ? $options{type} : 'deb';
my $arch = $options{arch};

my @find_args;
if ($options{arch}) {
     @find_args = ('(', '-name', "*_all.$type", '-o',
			'-name', "*_${arch}.$type", ')');
}
else {
     @find_args = ('-name', "*.$type");
}
push @find_args, '-follow';

my ($binarydir, $override, $pathprefix) = @ARGV;

-d $binarydir or error(_g("Binary dir %s not found"), $binarydir);
defined($override) and (-e $override or
    error(_g("Override file %s not found"), $override));

$pathprefix = '' if not defined $pathprefix;

my %vercache;
sub vercmp {
     my ($a,$b)=@_;
     return $vercache{$a}{$b} if exists $vercache{$a}{$b};
     $vercache{$a}{$b} = compare_versions($a, 'gt', $b);
     return $vercache{$a}{$b};
}

my $find_h = new IO::Handle;
open($find_h,'-|','find',"$binarydir/",@find_args,'-print')
     or syserr(_g("Couldn't open %s for reading"), $binarydir);
FILE:
    while (<$find_h>) {
	chomp;
	my $fn = $_;
	my $control = `dpkg-deb -I $fn control`;
	if ($control eq "") {
	    warning(_g("Couldn't call dpkg-deb on %s: %s, skipping package"),
	            $fn, $!);
	    next;
	}
	if ($?) {
	    warning(_g("\`dpkg-deb -I %s control' exited with %d, skipping package"),
	            $fn, $?);
	    next;
	}
	
	my $fields = Dpkg::Control->new(type => CTRL_APT_PKG);
	my $temp = $control;
	while ($temp =~ s/^\n*(\S+):[ \t]*(.*(\n[ \t].*)*)\n//) {
	    my ($key, $value) = ($1, $2);
	    $value =~ s/\s+$//;
	    $fields->{$key} = $value;
	}
	$temp =~ /^\n*$/
	    or error(_g("Unprocessed text from %s control file; info:\n%s / %s"),
	             $fn, $control, $temp);
	
	defined($fields->{'Package'})
	    or error(_g("No Package field in control file of %s"), $fn);
	my $p = $fields->{'Package'};
	
	if (defined($packages{$p}) and not $options{multiversion}) {
	    foreach (@{$packages{$p}}) {
		if (vercmp($fields->{'Version'}, $_->{'Version'})) {
		    warning(_g("Package %s (filename %s) is repeat but newer version;"),
		            $p, $fn);
		    warning(_g("used that one and ignored data from %s!"),
		            $_->{Filename});
		    $packages{$p} = [];
		} else {
		    warning(_g("Package %s (filename %s) is repeat;"), $p, $fn);
		    warning(_g("ignored that one and using data from %s!"),
		            $_->{Filename});
		    next FILE;
		}
	    }
	}
	warning(_g("Package %s (filename %s) has Filename field!"), $p, $fn)
	    if defined($fields->{'Filename'});
	
	$fields->{'Filename'} = "$pathprefix$fn";
	
        my $sums = {};
        my $size;
        getchecksums($fn, $sums, \$size);
        foreach my $alg (@check_supported) {
            if ($alg eq "md5") {
	        $fields->{'MD5sum'} = $sums->{'md5'};
            } else {
                $fields->{$alg} = $sums->{$alg};
            }
        }
	$fields->{'Size'} = $size;
        $fields->{'X-Medium'} = $options{medium} if defined $options{medium};
	
	push @{$packages{$p}}, $fields;
    }
close($find_h);

load_override($override) if defined $override;
load_override_extra($options{'extra-override'}) if defined $options{'extra-override'};

my @missingover=();

my $records_written = 0;
for my $p (sort keys %packages) {
    if (defined($override) and not defined($overridden{$p})) {
        push(@missingover,$p);
    }
    for my $package (@{$packages{$p}}) {
	 print(STDOUT "$package\n") or syserr(_g("Failed when writing stdout"));
         $records_written++;
    }
}
close(STDOUT) or syserr(_g("Couldn't close stdout"));

if (@changedmaint) {
    warning(_g("Packages in override file with incorrect old maintainer value:"));
    warning($_) foreach (@changedmaint);
}
if (@samemaint) {
    warning(_g("Packages specifying same maintainer as override file:"));
    warning($_) foreach (@samemaint);
}
if (@missingover) {
    warning(_g("Packages in archive but missing from override file:"));
    warning("  %s", join(' ', @missingover));
}
if (@spuriousover) {
    warning(_g("Packages in override file but not in archive:"));
    warning("  %s", join(' ', @spuriousover));
}

info(_g("Wrote %s entries to output Packages file."), $records_written);

