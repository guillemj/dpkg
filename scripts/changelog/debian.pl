#!/usr/bin/perl
#
# parsechangelog/debian
#
# Copyright © 1996 Ian Jackson
# Copyright © 2005,2007 Frank Lichtenheld
# Copyright © 2006-2012 Guillem Jover <guillem@debian.org>
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

use Getopt::Long qw(:config posix_default bundling no_ignorecase);
use POSIX;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Changelog::Debian;

textdomain("dpkg-dev");

$progname = "parsechangelog/$progname";

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
This is free software; see the GNU General Public License version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option>...] [<changelogfile>]

Options:
    -?, --help                  print usage information
    --version, -V               print version information
    --label, -l <file>          name of the changelog file to
                                use in error messages
    --file <file>               changelog file to parse, defaults
                                to '-' (standard input)
    --format <outputformat>     see man page for list of available
                                output formats, defaults to 'dpkg'
                                for compatibility with dpkg-dev
    --since, -s, -v <version>   include all changes later than version
    --until, -u <version>       include all changes earlier than version
    --from, -f <version>        include all changes equal or later
                                than version
    --to, -t <version>          include all changes up to or equal
                                than version
    --count, -c, -n <number>    include <number> entries from the top
                                (or the tail if <number> is lower than 0)
    --offset, -o <number>       change the starting point for --count,
                                counted from the top (or the tail if
                                <number> is lower than 0)
    --all                       include all changes
"), $progname;
}

my ( $since, $until, $from, $to, $all, $count, $offset, $file, $label );
my $default_file = '-';
my $format = 'dpkg';
my %allowed_formats = (
    dpkg => 1,
    rfc822 => 1,
    );

sub set_format {
    my ($opt, $val) = @_;

    unless ($allowed_formats{$val}) {
	usageerr(_g('output format %s not supported'), $val );
    }

    $format = $val;
}

GetOptions( "file=s" => \$file,
	    "label|l=s" => \$label,
	    "since|v=s" => \$since,
	    "until|u=s" => \$until,
	    "from|f=s" => \$from,
	    "to|t=s" => \$to,
	    "count|c|n=i" => \$count,
	    "offset|o=i" => \$offset,
	    "help|?" => sub{ usage(); exit(0) },
	    "version|V" => sub{version();exit(0)},
	    "format=s" => \&set_format,
	    "all|a" => \$all,
	    )
    or do { usage(); exit(2) };

usageerr('too many arguments') if @ARGV > 1;

if (@ARGV) {
    if ($file && ($file ne $ARGV[0])) {
	usageerr(_g('more than one file specified (%s and %s)'),
		 $file, $ARGV[0] );
    }
    $file = $ARGV[0];
}

$file ||= $default_file;
$label ||= $file;
unless (defined($since) or defined($until) or defined($from) or
        defined($to) or defined($offset) or defined($count) or
        defined($all))
{
    $count = 1;
}
my %all = $all ? ( all => $all ) : ();
my $range = {
    since => $since, until => $until, from => $from, to => $to,
    count => $count, offset => $offset,
    %all
};

my $changes = Dpkg::Changelog::Debian->new(reportfile => $label, range => $range);

if ($file eq '-') {
    $changes->parse(\*STDIN, _g("<standard input>"))
	or error(_g('fatal error occurred while parsing input'));
} else {
    $changes->load($file)
	or error(_g('fatal error occurred while parsing %s'), $file);
}

eval qq{
    my \$output = \$changes->$format(\$range);
    print \$output if defined \$output;
};
if ($@) {
    error("%s", $@);
}
