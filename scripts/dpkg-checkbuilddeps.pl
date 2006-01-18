#!/usr/bin/perl
# GPL copyright 2001 by Joey Hess <joeyh@debian.org>

#use strict;
use Getopt::Long;

my $dpkglibdir="/usr/lib/dpkg";
push(@INC,$dpkglibdir);
#my $controlfile;
require 'controllib.pl';

sub usage {
	print STDERR <<EOF;
Usage: dpkg-checkbuilddeps [-B] [control-file]
	-B		binary-only, ignore -Indep
	control-file	control file to process [Default: debian/control]
EOF
}

my ($me)=$0=~m:.*/(.+):;

my $binary_only=0;
my $want_help=0;
if (! GetOptions('-B' => \$binary_only,
		 '-h' => \$want_help)) {
	usage();
	exit(2);
}
if ($want_help) {
	usage();
	exit(0);
}

my $control=shift || "debian/control";
$controlfile=$control;

&parsecontrolfile;
my @status=parse_status();
my (@unmet, @conflicts);
local $/='';

my $dep_regex=qr/[ \t]*(([^\n]+|\n[ \t])*)\s/; # allow multi-line
if (defined($fi{"C Build-Depends"})) {
	push @unmet, build_depends('Build-Depends',
				   parsedep($fi{"C Build-Depends"}, 1, 1),
				   @status);
}
if (defined($fi{"C Build-Conflicts"})) {
	push @conflicts, build_conflicts('Build-Conflicts',
					 parsedep($fi{"C Build-Conflicts"}, 1, 1),
					 @status);
}
if (! $binary_only && defined($fi{"C Build-Depends-Indep"})) {
	push @unmet, build_depends('Build-Depends-Indep',
				   parsedep($fi{"C Build-Depends-Indep"}, 1, 1),
				   @status);
}
if (! $binary_only && defined($fi{"C Build-Conflicts-Indep"})) {
	push @conflicts, build_conflicts('Build-Conflicts-Indep',
					 parsedep($fi{"C Build-Conflicts-Indep"}, 1, 1),
					 @status);
}

if (@unmet) {
	print STDERR "$me: Unmet build dependencies: ";
	print STDERR join(" ", @unmet), "\n";
}
if (@conflicts) {
	print STDERR "$me: Build conflicts: ";
	print STDERR join(" ", @conflicts), "\n";
}
exit 1 if @unmet || @conflicts;

# This part could be replaced. Silly little status file parser.
# thanks to Matt Zimmerman. Returns two hash references that
# are exactly what the other functions need...
sub parse_status {
	my $status=shift || "/var/lib/dpkg/status";
	
	my %providers;
	my %version;
	local $/ = '';
	open(STATUS, "<$status") || die "$status: $!\n";
	while (<STATUS>) {
		next unless /^Status: .*ok installed$/m;
	
		my ($package) = /^Package: (.*)$/m;
		push @{$providers{$package}}, $package;
		($version{$package}) = /^Version: (.*)$/m;
	
		if (/^Provides: (.*)$/m) {
			foreach (split(/,\s*/, $1)) {
				push @{$providers{$_}}, $package;
			}
		}
	}
	close STATUS;

	return \%version, \%providers;
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
	my %version=%{shift()};
	my %providers=%{shift()};
	my $host_arch=shift || `dpkg-architecture -qDEB_HOST_ARCH`;
	chomp $host_arch;

	my @unmet=();

	unless(defined($dep_list)) {
	    &error("error occurred while parsing $fieldname");
	}

	foreach my $dep_and (@$dep_list) {
		my $ok=0;
		my @possibles=();
ALTERNATE:	foreach my $alternate (@$dep_and) {
			my ($package, $relation, $version, $arch_list)= @{$alternate};

			# This is a possibile way to meet the dependency.
			# Remove the arch stuff from $alternate.
			push @possibles, $package . ($relation && $version ? " ($relation $version)" : '');
	
			if ($relation && $version) {
				if (! exists $version{$package}) {
					# Not installed at all, so fail.
					next;
				}
				else {
					# Compare installed and needed
					# version number.
					system("dpkg", "--compare-versions",
						$version{$package}, $relation,
						 $version);
					if (($? >> 8) != 0) {
						next; # fail
					}
				}
			}
			elsif (! defined $providers{$package}) {
				# It's not a versioned dependency, and
				# nothing provides it, so fail.
				next;
			}
			# If we get to here, the dependency was met.
			$ok=1;
		}
	
		if (@possibles && (($build_depends && ! $ok) ||
		                   (! $build_depends && $ok))) {
			# TODO: this could return a more complex
			# data structure instead to save re-parsing.
			push @unmet, join (" | ", @possibles);
		}
	}

	return @unmet;
}
