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

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;

textdomain("dpkg");

($0) = $0 =~ m:.*/(.+):;

sub version {
    printf _g("Debian %s version %s.\n"), $0, $version;

    printf _g("
Copyright (C) 1996 Kim-Minh Kaplan.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] [--] [<dirname>]

Options:
  --unsafe     set some additional possibly useful options.
               warning: this option may garble an otherwise correct file.
  --help       show this help message.
  --version    show the version.
"), $0;
}

my $infodir = '/usr/info';
my $unsafe = 0;
$0 =~ m|[^/]+$|;
my $name= $&;

sub ulquit {
    unlink "$infodir/dir.lock"
	or warn sprintf(_g("%s: warning - unable to unlock %s: %s"),
	                $name, "$infodir/dir", $!)."\n";
    die "$name: $_[0]";
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
    printf STDERR _g("%s: unknown option \`%s'")."\n", $name, $_;
    usage;
    exit 1;
}

if (scalar @ARGV > 0) {
    $infodir = shift;
    if (scalar @ARGV > 0) {
	printf STDERR _g("%s: too many arguments")."\n", $name;
	usage;
	exit 1;
    }
}

if (!link "$infodir/dir", "$infodir/dir.lock") {
    die sprintf(_g("%s: failed to lock dir for editing! %s"),
                $name, $!)."\n".
        ($! =~ /exist/i ? sprintf(_g("try deleting %s"),
                                  "$infodir/dir.lock")."\n" : '');
}
open OLD, "$infodir/dir"
    or ulquit sprintf(_g("unable to open %s: %s"), "$infodir/dir", $!)."\n";
open OUT, ">$infodir/dir.new"
    or ulquit sprintf(_g("unable to create %s: %s"), "$infodir/dir.new", $!)."\n";

my (%sections, @section_list, $lastline);
my $section="Miscellaneous";	# default section
my $section_canonic="miscellaneous";
my $waitfor = $unsafe ? '^\*.*:' : '^\*\s*Menu';

while (<OLD>) {				# dump the non entries part
    last if (/$waitfor/oi);
    if (defined $lastline) {
	print OUT $lastline
	    or ulquit sprintf(_g("unable to write %s: %s"),
				 "$infodir/dir.new", $!)."\n";
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

eof OLD or ulquit sprintf(_g("unable to read %s: %s"), "$infodir/dir", $!)."\n";
close OLD or ulquit sprintf(_g("unable to close %s after read: %s"),
                               "$infodir/dir", $!)."\n";

print OUT @sections{@section_list};
close OUT or ulquit sprintf(_g("unable to close %s: %s"),
                               "$infodir/dir.new", $!)."\n";

# install clean version
unlink "$infodir/dir.old";
link "$infodir/dir", "$infodir/dir.old"
    or ulquit sprintf(_g("unable to backup old %s, giving up: %s"),
                         "$infodir/dir", $!)."\n";
rename "$infodir/dir.new", "$infodir/dir"
    or ulquit sprintf(_g("failed to install %s; it will be left as %s: %s"),
                         "$infodir/dir", "$infodir/dir.new", $!)."\n";

unlink "$infodir/dir.lock"
    or die sprintf(_g("%s: unable to unlock %s: %s"),
                   $name, "$infodir/dir", $!)."\n";

exit 0;
