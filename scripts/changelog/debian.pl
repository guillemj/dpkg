#!/usr/bin/perl
#
# parsechangelog/debian
#
# Copyright © 1996 Ian Jackson
# Copyright © 2005,2007 Frank Lichtenheld
# Copyright © 2006-2014 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Getopt::Long qw(:config posix_default bundling no_ignorecase);

use Dpkg ();
use Dpkg::Util qw(none);
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Changelog::Debian;

textdomain('dpkg-dev');

$Dpkg::PROGNAME = "parsechangelog/$Dpkg::PROGNAME";

sub version {
    printf g_("Debian %s version %s.\n"), $Dpkg::PROGNAME, $Dpkg::PROGVERSION;

    printf g_('
This is free software; see the GNU General Public License version 2 or
later for copying conditions. There is NO warranty.
');
}

sub usage {
    printf g_(
'Usage: %s [<option>...] [<changelog-file>]')
    . "\n\n" . g_(
"Options:
      --file <file>       changelog <file> to parse (defaults to '-').
  -l, --label <file>      changelog <file> name to use in error messages.
      --format <output-format>
                          set the output format (defaults to 'dpkg').
      --all               include all changes.
  -s, --since <version>   include all changes later than <version>.
  -v <version>            ditto.
  -u, --until <version>   include all changes earlier than <version>.
  -f, --from <version>    include all changes equal or later than <version>.
  -t, --to <version>      include all changes up to or equal than <version>.
  -c, --count <number>    include <number> entries from the top (or tail if
                            <number> is lower than 0).
  -n <number>             ditto.
  -o, --offset <number>   change starting point for --count, counted from
                            the top (or tail if <number> is lower than 0).
  -?, --help              print usage information.
  -V, --version           print version information.
"), $Dpkg::PROGNAME;
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
	usageerr(g_('output format %s not supported'), $val );
    }

    $format = $val;
}

my @options_spec = (
    'file=s' => \$file,
    'label|l=s' => \$label,
    'since|v=s' => \$since,
    'until|u=s' => \$until,
    'from|f=s' => \$from,
    'to|t=s' => \$to,
    'count|c|n=i' => \$count,
    'offset|o=i' => \$offset,
    'help|?' => sub{ usage(); exit(0) },
    'version|V' => sub{version();exit(0)},
    'format=s' => \&set_format,
    'all|a' => \$all,
);

{
    local $SIG{__WARN__} = sub { usageerr($_[0]) };
    GetOptions(@options_spec);
}

usageerr('too many arguments') if @ARGV > 1;

if (@ARGV) {
    if ($file && ($file ne $ARGV[0])) {
	usageerr(g_('more than one file specified (%s and %s)'),
		 $file, $ARGV[0] );
    }
    $file = $ARGV[0];
}

$file //= $default_file;
$label //= $file;

my %all = $all ? ( all => $all ) : ();
my $range = {
    since => $since, until => $until, from => $from, to => $to,
    count => $count, offset => $offset,
    %all
};
if (none { defined $range->{$_} } qw(since until from to offset count all)) {
    $range->{count} = 1;
}

my $changes = Dpkg::Changelog::Debian->new(reportfile => $label, range => $range);

$changes->load($file)
    or error(g_('fatal error occurred while parsing %s'), $file);

eval qq{
    my \$output = \$changes->$format(\$range);
    print \$output if defined \$output;
};
if ($@) {
    error('%s', $@);
}
