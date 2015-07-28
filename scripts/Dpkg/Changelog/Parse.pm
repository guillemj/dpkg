# Copyright © 2005, 2007 Frank Lichtenheld <frank@lichtenheld.de>
# Copyright © 2009       Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2010, 2012-2015 Guillem Jover <guillem@debian.org>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

=encoding utf8

=head1 NAME

Dpkg::Changelog::Parse - generic changelog parser for dpkg-parsechangelog

=head1 DESCRIPTION

This module provides a set of functions which reproduce all the features
of dpkg-parsechangelog.

=cut

package Dpkg::Changelog::Parse;

use strict;
use warnings;

our $VERSION = '1.01';
our @EXPORT = qw(
    changelog_parse_plugin
    changelog_parse
);

use Exporter qw(import);

use Dpkg ();
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control::Changelog;

=head1 FUNCTIONS

=over 4

=item $fields = changelog_parse_plugin(%opt)

This function will parse a changelog. In list context, it returns as many
Dpkg::Control objects as the parser did output. In scalar context, it will
return only the first one. If the parser did not return any data, it will
return an empty list in list context or undef on scalar context. If the
parser failed, it will die.

The parsing itself is done by an external program (searched in the
following list of directories: $opt{libdir},
F</usr/local/lib/dpkg/parsechangelog>, F</usr/lib/dpkg/parsechangelog>).
That program is named according to the format that it is able to parse. By
default it is either "debian" or the format name looked up in the 40 last
lines of the changelog itself (extracted with this perl regular expression
"\schangelog-format:\s+([0-9a-z]+)\W"). But it can be overridden
with $opt{changelogformat}. The program expects the content of the
changelog file on its standard input.

The changelog file that is parsed is F<debian/changelog> by default but it
can be overridden with $opt{file}.

All the other keys in %opt are forwarded as parameter to the external
parser. If the key starts with "-", it is passed as is. If not, it is passed
as "--<key>". If the value of the corresponding hash entry is defined, then
it is passed as the parameter that follows.

=cut

sub changelog_parse_plugin {
    my (%options) = @_;

    # Setup and sanity checks.
    $options{file} //= 'debian/changelog';
    my $changelogfile = $options{file};

    my @parserpath = ('/usr/local/lib/dpkg/parsechangelog',
                      "$Dpkg::LIBDIR/parsechangelog",
                      '/usr/lib/dpkg/parsechangelog');
    my $format = 'debian';
    my $force = 0;

    # Extract and remove options that do not concern the changelog parser
    # itself (and that we shouldn't forward)
    if (exists $options{libdir}) {
	unshift @parserpath, $options{libdir};
	delete $options{libdir};
    }
    if (exists $options{changelogformat}) {
	$format = $options{changelogformat};
	delete $options{changelogformat};
	$force = 1;
    }

    # Extract the format from the changelog file if possible
    unless ($force or ($changelogfile eq '-')) {
	local $_;

	open(my $format_fh, '-|', 'tail', '-n', '40', $changelogfile)
	    or syserr(g_('cannot create pipe for %s'), 'tail');
	while (<$format_fh>) {
	    $format = $1 if m/\schangelog-format:\s+([0-9a-z]+)\W/;
	}
	close($format_fh) or subprocerr(g_('tail of %s'), $changelogfile);
    }

    # Find the right changelog parser
    my $parser;
    foreach my $dir (@parserpath) {
        my $candidate = "$dir/$format";
	next if not -e $candidate;
	if (-x _) {
	    $parser = $candidate;
	    last;
	} else {
	    warning(g_('format parser %s not executable'), $candidate);
	}
    }
    error(g_('changelog format %s is unknown'), $format) if not defined $parser;

    # Create the arguments for the changelog parser
    my @exec = ($parser, "-l$changelogfile");
    foreach my $option (keys %options) {
	if ($option =~ m/^-/) {
	    # Options passed untouched
	    push @exec, $option;
	} else {
	    # Non-options are mapped to long options
	    push @exec, "--$option";
	}
	push @exec, $options{$option} if defined $options{$option};
    }

    # Fork and call the parser
    my $pid = open(my $parser_fh, '-|');
    syserr(g_('cannot fork for %s'), $parser) unless defined $pid;
    if (not $pid) {
        exec @exec or syserr(g_('cannot execute format parser: %s'), $parser);
    }

    # Get the output into several Dpkg::Control objects
    my (@res, $fields);
    while (1) {
        $fields = Dpkg::Control::Changelog->new();
        last unless $fields->parse($parser_fh, g_('output of changelog parser'));
	push @res, $fields;
    }
    close($parser_fh) or subprocerr(g_('changelog parser %s'), $parser);
    if (wantarray) {
	return @res;
    } else {
	return $res[0] if (@res);
	return;
    }
}

=item $fields = changelog_parse(%opt)

This function will parse a changelog. In list context, it returns as many
Dpkg::Control objects as the parser did create. In scalar context, it will
return only the first one. If the parser did not return any data, it will
return an empty list in list context or undef on scalar context. If the
parser failed, it will die.

The changelog file that is parsed is F<debian/changelog> by default but it
can be overridden with $opt{file}.

=cut

sub changelog_parse {
    my (%options) = @_;

    return changelog_parse_plugin(%options);
}

=back

=head1 CHANGES

=head2 Version 1.01 (dpkg 1.18.2)

New functions: changelog_parse_plugin().

=head2 Version 1.00 (dpkg 1.15.6)

Mark the module as public.

=cut

1;
