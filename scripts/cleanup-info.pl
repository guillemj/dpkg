#!/usr/bin/perl --
#
#   Clean up the mess that bogus install-info may have done :
#
#	- gather all sections with the same heading into a single one.
#	Tries to be smart about cases and trailing colon/spaces.
#
#   Other clean ups :
#
#	- remove empty sections,
#	- squeeze blank lines (in entries part only).
#
#   Order of sections is preserved (the first encountered section
# counts).
#
#   Order of entries within a section is preserved.
#
# BUGS:
#
#   Probably many : I just recently learned Perl for this program
# using the man pages.  Hopefully this is a short enough program to
# debug.

# don't put that in for production.
# use strict;

my $version = '1.1.6'; # This line modified by Makefile
sub version {
    print STDERR <<END;
Debian cleanup-info $version.  Copyright (C)1996 Kim-Minh Kaplan.
This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.
END
}

sub usage {
    print STDERR <<'EOF';
usage: cleanup-info [--version] [--help] [--unsafe] [--] [<dirname>]
Warning: the ``--unsafe'' option may garble an otherwise correct file
EOF
}

my $infodir = '/usr/info';
my $unsafe = 0;
$0 =~ m|[^/]+$|;
my $name= $&;

sub ulquit {
    unlink "$infodir/dir.lock"
	or warn "$name: warning - unable to unlock $infodir/dir: $!\n";
    die $_[0];
}

while (scalar @ARGV > 0 && $ARGV[0] =~ /^--/) {
    $_ = shift;
    /^--$/ and last;
    /^--version$/ and do {
	version;
	exit 0;
    };
    /^--help$/ and do {
	usage;
	exit 0;
    };
    /^--unsafe$/ and do {
	$unsafe=1;
	next;
    };
    print STDERR "$name: unknown option \`$_'\n";
    usage;
    exit 1;
}

if (scalar @ARGV > 0) {
    $infodir = shift;
    if (scalar @ARGV > 0) {
	print STDERR "$name: too many arguments\n";
	usage;
	exit 1;
    }
}

if (!link "$infodir/dir", "$infodir/dir.lock") {
    die "$name: failed to lock dir for editing! $!\n".
        ($! =~ /exist/i ? "try deleting $infodir/dir.lock\n" : '');
}
open OLD, "$infodir/dir"  or ulquit "$name: can't open $infodir/dir: $!\n";
open OUT, ">$infodir/dir.new"
    or ulquit "$name can't create $infodir/dir.new: $!\n";

my (%sections, @section_list, $lastline);
my $section="Miscellaneous";	# default section
my $section_canonic="miscellaneous";
my $waitfor = $unsafe ? '^\*.*:' : '^\*\s*Menu';

while (<OLD>) {				# dump the non entries part
    last if (/$waitfor/oi);
    if (defined $lastline) {
	print OUT $lastline
	    or ulquit "$name: error writing $infodir/dir.new: $!\n";
    }
    $lastline = $_;
};

if (/^\*\s*Menu\s*:?/i) {
    print OUT $lastline if defined $lastline;
    print OUT $_;
} else {
    print OUT "* Menu:\n";
    if (defined $lastline) {
	$lastline =~ s/\s*$//;
	if ($lastline =~ /^([^\*\s].*)/) { # there was a section title
	    $section = $1;
	    $lastline =~ s/\s*:$//;
	    $section_canonic = lc $lastline;
	}
    }
    push @section_list, $section_canonic;
    s/\s*$//;
    $sections{$section_canonic} = "\n$section\n$_\n";
}

foreach (<OLD>) {		# collect sections
    next if (/^\s*$/ or $unsafe and /^\*\s*Menu/oi);
    s/\s*$//;
    if (/^([^\*\s].*)/) {		# change of section
	$section = $1;
	s/\s*:$//;
	$section_canonic = lc $_;
    } else {			# add to section
	if (! exists $sections{$section_canonic}) { # create section header
	    push @section_list, $section_canonic;
	    $sections{$section_canonic} = "\n$section\n";
	}
	$sections{$section_canonic} .= "$_\n";
    }
}

eof OLD or ulquit "$name: read $infodir/dir: $!\n";
close OLD or ulquit "$name: close $infodir/dir after read: $!\n";

print OUT @sections{@section_list};
close OUT or ulquit "$name: error closing $infodir/dir.new: $!\n";

# install clean version
unlink "$infodir/dir.old";
link "$infodir/dir", "$infodir/dir.old"
    or ulquit "$name: can't backup old $infodir/dir, giving up: $!\n";
rename "$infodir/dir.new", "$infodir/dir"
    or ulquit "$name: failed to install $infodir/dir; I'll leave it as $infodir/dir.new: $!\n";

unlink "$infodir/dir.lock"
    or die "$name: failed to unlock $infodir/dir: $!\n";

exit 0;
