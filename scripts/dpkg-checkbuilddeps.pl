#!/usr/bin/perl -w
# GPL copyright 2001 by Joey Hess <joeyh@debian.org>

use strict;
use Getopt::Long;

sub usage {
	print STDERR <<EOF;
Usage: dpkg-checkbuild [-B] [control-file]
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

open (CONTROL, $control) || die "$control: $!\n";
my @status=parse_status();
my (@unmet, @conflicts);
local $/='';
my $cdata=<CONTROL>;
close CONTROL;

my $dep_regex=qr/\s*((.|\n\s+)*)\s/; # allow multi-line
if ($cdata =~ /^Build-Depends:$dep_regex/mi) {
	push @unmet, build_depends($1, @status);
}
if ($cdata =~ /^Build-Conflicts:$dep_regex/mi) {
	push @conflicts, build_conflicts($1, @status);
}
if (! $binary_only && $cdata =~ /^Build-Depends-Indep:$dep_regex/mi) {
	push @unmet, build_depends($1, @status);
}
if (! $binary_only && $cdata =~ /^Build-Conflicts-Indep:$dep_regex/mi) {
	push @conflicts, build_conflicts($1, @status);
}

if (@unmet) {
	print STDERR "$me: Unmet build dependencies: ";
	print STDERR join(", ", @unmet), "\n";
}
if (@conflicts) {
	print STDERR "$me: Build conflicts: ";
	print STDERR join(", ", @conflicts), "\n";
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
	my $line=shift;
	my %version=%{shift()};
	my %providers=%{shift()};
	my $host_arch=shift || `dpkg-architecture -qDEB_HOST_ARCH`;
	chomp $host_arch;

	my @unmet=();
	foreach my $dep (split(/,\s*/, $line)) {
		my $ok=0;
		my @possibles=();
ALTERNATE:	foreach my $alternate (split(/\s*\|\s*/, $dep)) {
			my ($package, $rest)=split(/\s*(?=[[(])/, $alternate, 2);
			$package =~ s/\s*$//;

			# Check arch specifications.
			if (defined $rest && $rest=~m/\[(.*?)\]/) {
				my $arches=lc($1);
				my $seen_arch='';
				foreach my $arch (split(' ', $arches)) {
					if ($arch eq $host_arch) {
						$seen_arch=1;
						next;
					}
					elsif ($arch eq "!$host_arch") {
						next ALTERNATE;
					}
					elsif ($arch =~ /!/) {
						# This is equivilant to
						# having seen the current arch,
						# unless the current arch
						# is also listed..
						$seen_arch=1;
					}
				}
				if (! $seen_arch) {
					next;
				}
			}
			
			# This is a possibile way to meet the dependency.
			# Remove the arch stuff from $alternate.
			$alternate=~s/\s+\[.*?\]//;
			push @possibles, $alternate;
	
			# Check version.
			if (defined $rest && $rest=~m/\(\s*([<>=]{1,2})\s*(.*?)\s*\)/) {
				my $relation=$1;
				my $version=$2;
				
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
