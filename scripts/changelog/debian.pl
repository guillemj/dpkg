#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(:config gnu_getopt auto_help);
use POSIX;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(usageerr failure);
use Dpkg::Changelog::Debian;

textdomain("dpkg-dev");

$progname = "parsechangelog/$progname";

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2005,2007 Frank Lichtenheld.");
    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option>...] [<changelogfile>]

Options:
    --help, -h                  print usage information
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
	    "help|h" => sub{usage();exit(0)},
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

my $changes = Dpkg::Changelog::Debian->init();

$file ||= $default_file;
$label ||= $file;
unless ($since or $until or $from or $to or
	$offset or $count or $all) {
    $count = 1;
}
my @all = $all ? ( all => $all ) : ();
my $opts = { since => $since, until => $until,
	     from => $from, to => $to,
	     count => $count, offset => $offset,
	     @all, reportfile => $label };

if ($file eq '-') {
    $changes->parse({ inhandle => \*STDIN, %$opts })
	or failure(_g('fatal error occured while parsing input'));
} else {
    $changes->parse({ infile => $file, %$opts })
	or failure(_g('fatal error occured while parsing %s'),
		   $file );
}


eval("print \$changes->${format}_str(\$opts)");
if ($@) {
    failure("%s",$@);
}
