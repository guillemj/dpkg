#!/usr/bin/perl
# GPL copyright 2001 by Joey Hess <joeyh@debian.org>

use strict;
use warnings;

use Getopt::Long;
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error);
use Dpkg::Arch qw(get_host_arch);
use Dpkg::Deps;
use Dpkg::Control;

textdomain("dpkg-dev");

sub usage {
	printf _g(
"Usage: %s [<option> ...] [<control-file>]

Options:
  control-file   control file to process (default: debian/control).
  -B             binary-only, ignore -Indep.
  -d build-deps  use given string as build dependencies instead of
                 retrieving them from control file
  -c build-conf  use given string for build conflicts instead of
                 retrieving them from control file
  --admindir=<directory>
                 change the administrative directory.
  -h             show this help message.
"), $progname;
}

my $binary_only=0;
my $want_help=0;
my ($bd_value, $bc_value);
if (! GetOptions('-B' => \$binary_only,
		 '-h' => \$want_help,
		 '-d=s' => \$bd_value,
		 '-c=s' => \$bc_value,
		 '--admindir=s' => \$admindir)) {
	usage();
	exit(2);
}
if ($want_help) {
	usage();
	exit(0);
}

my $controlfile = shift || "debian/control";

my $control = Dpkg::Control->new($controlfile);
my $fields = $control->get_source();

my $facts = parse_status("$admindir/status");

unless (defined($bd_value) or defined($bc_value)) {
    $bd_value = 'build-essential';
    $bd_value .= ", " . $fields->{"Build-Depends"} if defined $fields->{"Build-Depends"};
    if (not $binary_only and defined $fields->{"Build-Depends-Indep"}) {
	$bd_value .= ", " . $fields->{"Build-Depends-Indep"};
    }
    $bc_value = $fields->{"Build-Conflicts"} if defined $fields->{"Build-Conflicts"};
    if (not $binary_only and defined $fields->{"Build-Conflicts-Indep"}) {
	if ($bc_value) {
	    $bc_value .= ", " . $fields->{"Build-Conflicts-Indep"};
	} else {
	    $bc_value = $fields->{"Build-Conflicts-Indep"};
	}
    }
}
my (@unmet, @conflicts);

if ($bd_value) {
	push @unmet, build_depends('Build-Depends/Build-Depends-Indep)',
		Dpkg::Deps::parse($bd_value, reduce_arch => 1), $facts);
}
if ($bc_value) {
	push @conflicts, build_conflicts('Build-Conflicts/Build-Conflicts-Indep',
		Dpkg::Deps::parse($bc_value, reduce_arch => 1, union => 1), $facts);
}

if (@unmet) {
	printf STDERR _g("%s: Unmet build dependencies: "), $progname;
	print STDERR join(" ", map { $_->dump() } @unmet), "\n";
}
if (@conflicts) {
	printf STDERR _g("%s: Build conflicts: "), $progname;
	print STDERR join(" ", map { $_->dump() } @conflicts), "\n";
}
exit 1 if @unmet || @conflicts;

# Silly little status file parser that returns a Dpkg::Deps::KnownFacts
sub parse_status {
	my $status = shift;
	
	my $facts = Dpkg::Deps::KnownFacts->new();
	local $/ = '';
	open(STATUS, "<$status") || die "$status: $!\n";
	while (<STATUS>) {
		next unless /^Status: .*ok installed$/m;
	
		my ($package) = /^Package: (.*)$/m;
		my ($version) = /^Version: (.*)$/m;
		$facts->add_installed_package($package, $version);
	
		if (/^Provides: (.*)$/m) {
			my $provides = Dpkg::Deps::parse($1,
                            reduce_arch => 1, union => 1);
			next if not defined $provides;
			foreach (grep { $_->isa('Dpkg::Deps::Simple') }
                                 $provides->get_deps())
			{
				$facts->add_provided_package($_->{package},
                                    $_->{relation}, $_->{version},
                                    $package);
			}
		}
	}
	close STATUS;

	return $facts;
}

# This function checks the build dependencies passed in as the first
# parameter. If they are satisfied, returns false. If they are unsatisfied,
# an list of the unsatisfied depends is returned.
#
# Additional parameters that must be passed:
# * A reference to a hash of all "ok installed" the packages on the system,
#   with the hash key being the package name, and the value being the 
#   installed version.
# * A reference to a hash, where the keys are package names, and the
#   value is a true value iff some package installed on the system provides
#   that package (all installed packages provide themselves)
#
# Optionally, the architecture the package is to be built for can be passed
# in as the 4th parameter. If not set, dpkg will be queried for the build
# architecture.
sub build_depends {
	return check_line(1, @_);
}

# This function is exactly like unmet_build_depends, except it
# checks for build conflicts, and returns a list of the packages
# that are installed and are conflicted with.
sub build_conflicts {
	return check_line(0, @_);
}

# This function does all the work. The first parameter is 1 to check build
# deps, and 0 to check build conflicts.
sub check_line {
	my $build_depends=shift;
	my $fieldname=shift;
	my $dep_list=shift;
	my $facts=shift;
	my $host_arch = shift || get_host_arch();
	chomp $host_arch;

	my @unmet=();

	unless(defined($dep_list)) {
	    error(_g("error occurred while parsing %s"), $fieldname);
	}

	if ($build_depends) {
		$dep_list->simplify_deps($facts);
		if ($dep_list->is_empty()) {
			return ();
		} else {
			return $dep_list->get_deps();
		}
	} else { # Build-Conflicts
		my @conflicts = ();
		foreach my $dep ($dep_list->get_deps()) {
			if ($dep->get_evaluation($facts)) {
				push @conflicts, $dep;
			}
		}
		return @conflicts;
	}
}
