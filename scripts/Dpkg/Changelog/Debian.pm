#
# Dpkg::Changelog::Debian
#
# Copyright 1996 Ian Jackson
# Copyright 2005 Frank Lichtenheld <frank@lichtenheld.de>
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
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

=head1 NAME

Dpkg::Changelog::Debian - parse Debian changelogs

=head1 SYNOPSIS

    use Parse::DebianChangelog;

    my $chglog = Parse::DebianChangelog->init( { infile => 'debian/changelog',
                                                 HTML => { outfile => 'changelog.html' } );
    $chglog->html;

    # the following is semantically equivalent
    my $chglog = Parse::DebianChangelog->init();
    $chglog->parse( { infile => 'debian/changelog' } );
    $chglog->html( { outfile => 'changelog.html' } );

    my $changes = $chglog->dpkg_str( { since => '1.0-1' } );
    print $changes;

=head1 DESCRIPTION

Dpkg::Changelog::Debian parses Debian changelogs as described in the Debian
policy (version 3.6.2.1 at the time of this writing). See section
L<"SEE ALSO"> for locations where to find this definition.

The parser tries to ignore most cruft like # or /* */ style comments,
CVS comments, vim variables, emacs local variables and stuff from
older changelogs with other formats at the end of the file.
NOTE: most of these are ignored silently currently, there is no
parser error issued for them. This should become configurable in the
future.

=head2 METHODS

=cut

package Dpkg::Changelog::Debian;

use strict;
use warnings;

use Fcntl qw( :flock );
use English;
use Date::Parse;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::Changelog qw( :util );
use base qw(Dpkg::Changelog);

=pod

=head3 parse

Parses either the file named in configuration item C<infile>, the content
of the filehandle in configuration item C<inhandle>, or the string
saved in configuration item C<instring> (the latter requires IO::String).
You can set a filename to use for reporting errors with configuration
item C<reportfile>.
Accepts a hash ref as optional argument which can contain configuration
items.

Returns C<undef> in case of error (e.g. "file not found", B<not> parse
errors) and the object if successful. If C<undef> was returned, you
can get the reason for the failure by calling the L<get_error> method.

=cut

sub parse {
    my ($self, $config) = @_;

    foreach my $c (keys %$config) {
	$self->{config}{$c} = $config->{$c};
    }

    my ($fh, $file);
    if ($file = $self->{config}{infile}) {
	open $fh, '<', $file or do {
	    $self->_do_fatal_error( _g("can't open file %s: %s"),
					$file, $! );
	    return undef;
	};
    } elsif ($fh = $self->{config}{inhandle}) {
	$file = 'FileHandle';
    } elsif (my $string = $self->{config}{instring}) {
	eval { require IO::String };
	if ($@) {
	    $self->_do_fatal_error( _g("can't load IO::String: %s"),
					$@ );
	    return undef;
	}
	$fh = IO::String->new( $string );
	$file = 'String';
    } else {
	$self->_do_fatal_error(_g('no changelog file specified'));
	return undef;
    }
    if (defined($self->{config}{reportfile})) {
	$file = $self->{config}{reportfile};
    }

    $self->reset_parse_errors;

    $self->{data} = [];

# based on /usr/lib/dpkg/parsechangelog/debian
    my $expect='first heading';
    my $entry = new Dpkg::Changelog::Entry;
    my $blanklines = 0;
    my $unknowncounter = 1; # to make version unique, e.g. for using as id

    while (<$fh>) {
	s/\s*\n$//;
#	printf(STDERR "%-39.39s %-39.39s\n",$expect,$_);
	my $name_chars = qr/[-+0-9a-z.]/i;
	if (m/^(\w$name_chars*) \(([^\(\) \t]+)\)((\s+$name_chars+)+)\;/i) {
	    unless ($expect eq 'first heading'
		    || $expect eq 'next heading or eof') {
		$entry->{ERROR} = [ $file, $NR,
				    sprintf(_g("found start of entry where expected %s"),
					    $expect), "$_" ];
		$self->_do_parse_error(@{$entry->{ERROR}});
	    }
	    unless ($entry->is_empty) {
		$entry->{'Closes'} = find_closes( $entry->{Changes} );
#		    print STDERR, Dumper($entry);
		push @{$self->{data}}, $entry;
		$entry = new Dpkg::Changelog::Entry;
		last if $self->_abort_early;
	    }
	    {
		$entry->{'Source'} = "$1";
		$entry->{'Version'} = "$2";
		$entry->{'Header'} = "$_";
		($entry->{'Distribution'} = "$3") =~ s/^\s+//;
		$entry->{'Changes'} = $entry->{'Urgency_comment'} = '';
		$entry->{'Urgency'} = $entry->{'Urgency_lc'} = 'unknown';
	    }
	    (my $rhs = $POSTMATCH) =~ s/^\s+//;
	    my %kvdone;
#	    print STDERR "RHS: $rhs\n";
	    for my $kv (split(/\s*,\s*/,$rhs)) {
		$kv =~ m/^([-0-9a-z]+)\=\s*(.*\S)$/i ||
		    $self->_do_parse_error($file, $NR,
					   sprintf(_g("bad key-value after \`;': \`%s'"), $kv));
		my $k = ucfirst $1;
		my $v = $2;
		$kvdone{$k}++ && $self->_do_parse_error($file, $NR,
							sprintf(_g("repeated key-value %s"), $k));
		if ($k eq 'Urgency') {
		    $v =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
			$self->_do_parse_error($file, $NR,
					      _g("badly formatted urgency value"),
					      $v);
		    $entry->{'Urgency'} = "$1";
		    $entry->{'Urgency_lc'} = lc("$1");
		    $entry->{'Urgency_comment'} = "$2";
		} elsif ($k =~ m/^X[BCS]+-/i) {
		    # Extensions - XB for putting in Binary,
		    # XC for putting in Control, XS for putting in Source
		    $entry->{$k}= $v;
		} else {
		    $self->_do_parse_error($file, $NR,
					   sprintf(_g("unknown key-value key %s - copying to XS-%s"), $k, $k));
		    $entry->{"XS-$k"} = $v;
		}
	    }
	    $expect= 'start of change data';
	    $blanklines = 0;
	} elsif (m/^(;;\s*)?Local variables:/io) {
	    last; # skip Emacs variables at end of file
	} elsif (m/^vim:/io) {
	    last; # skip vim variables at end of file
	} elsif (m/^\$\w+:.*\$/o) {
	    next; # skip stuff that look like a CVS keyword
	} elsif (m/^\# /o) {
	    next; # skip comments, even that's not supported
	} elsif (m,^/\*.*\*/,o) {
	    next; # more comments
	} elsif (m/^(\w+\s+\w+\s+\d{1,2} \d{1,2}:\d{1,2}:\d{1,2}\s+[\w\s]*\d{4})\s+(.*)\s+(<|\()(.*)(\)|>)/o
		 || m/^(\w+\s+\w+\s+\d{1,2},?\s*\d{4})\s+(.*)\s+(<|\()(.*)(\)|>)/o
		 || m/^(\w[-+0-9a-z.]*) \(([^\(\) \t]+)\)\;?/io
		 || m/^([\w.+-]+)(-| )(\S+) Debian (\S+)/io
		 || m/^Changes from version (.*) to (.*):/io
		 || m/^Changes for [\w.+-]+-[\w.+-]+:?$/io
		 || m/^Old Changelog:$/io
		 || m/^(?:\d+:)?\w[\w.+~-]*:?$/o) {
	    # save entries on old changelog format verbatim
	    # we assume the rest of the file will be in old format once we
	    # hit it for the first time
	    $self->{oldformat} = "$_\n";
	    $self->{oldformat} .= join "", <$fh>;
	} elsif (m/^\S/) {
	    $self->_do_parse_error($file, $NR,
				  _g("badly formatted heading line"), "$_");
	} elsif (m/^ \-\- (.*) <(.*)>(  ?)((\w+\,\s*)?\d{1,2}\s+\w+\s+\d{4}\s+\d{1,2}:\d\d:\d\d\s+[-+]\d{4}(\s+\([^\\\(\)]\))?)$/o) {
	    $expect eq 'more change data or trailer' ||
		$self->_do_parse_error($file, $NR,
				       sprintf(_g("found trailer where expected %s"),
					       $expect), "$_");
	    if ($3 ne '  ') {
		$self->_do_parse_error($file, $NR,
				       _g( "badly formatted trailer line" ),
				       "$_");
	    }
	    $entry->{'Trailer'} = $_;
	    $entry->{'Maintainer'} = "$1 <$2>" unless $entry->{'Maintainer'};
	    unless($entry->{'Date'} && defined $entry->{'Timestamp'}) {
		$entry->{'Date'} = "$4";
		$entry->{'Timestamp'} = str2time($4);
		unless (defined $entry->{'Timestamp'}) {
		    $self->_do_parse_error( $file, $NR,
					    sprintf(_g("couldn't parse date %s"),
						    "$4"));
		}
	    }
	    $expect = 'next heading or eof';
	} elsif (m/^ \-\-/) {
	    $entry->{ERROR} = [ $file, $NR,
				_g( "badly formatted trailer line" ), "$_" ];
	    $self->_do_parse_error(@{$entry->{ERROR}});
#	    $expect = 'next heading or eof'
#		if $expect eq 'more change data or trailer';
	} elsif (m/^\s{2,}(\S)/) {
	    $expect eq 'start of change data'
		|| $expect eq 'more change data or trailer'
		|| do {
		    $self->_do_parse_error($file, $NR,
					   sprintf(_g("found change data where expected %s"),
						   $expect), "$_");
		    if (($expect eq 'next heading or eof')
			&& !$entry->is_empty) {
			# lets assume we have missed the actual header line
			$entry->{'Closes'} = find_closes( $entry->{Changes} );
#		    print STDERR, Dumper($entry);
			push @{$self->{data}}, $entry;
			$entry = new Dpkg::Changelog::Entry;
			$entry->{Source} =
			    $entry->{Distribution} = $entry->{Urgency} =
			    $entry->{Urgency_LC} = 'unknown';
			$entry->{Version} = 'unknown'.($unknowncounter++);
			$entry->{Urgency_Comment} = '';
			$entry->{ERROR} = [ $file, $NR,
					    sprintf(_g("found change data where expected %s"),
						    $expect), "$_" ];
		    }
		};
	    $entry->{'Changes'} .= (" \n" x $blanklines)." $_\n";
	    if (!$entry->{'Items'} || ($1 eq '*')) {
		$entry->{'Items'} ||= [];
		push @{$entry->{'Items'}}, "$_\n";
	    } else {
		$entry->{'Items'}[-1] .= (" \n" x $blanklines)." $_\n";
	    }
	    $blanklines = 0;
	    $expect = 'more change data or trailer';
	} elsif (!m/\S/) {
	    next if $expect eq 'start of change data'
		|| $expect eq 'next heading or eof';
	    $expect eq 'more change data or trailer'
		|| $self->_do_parse_error($file, $NR,
					  sprintf(_g("found blank line where expected %s"),
						  $expect));
	    $blanklines++;
	} else {
	    $self->_do_parse_error($file, $NR, _g( "unrecognised line" ),
				   "$_");
	    ($expect eq 'start of change data'
		|| $expect eq 'more change data or trailer')
		&& do {
		    # lets assume change data if we expected it
		    $entry->{'Changes'} .= (" \n" x $blanklines)." $_\n";
		    if (!$entry->{'Items'}) {
			$entry->{'Items'} ||= [];
			push @{$entry->{'Items'}}, "$_\n";
		    } else {
			$entry->{'Items'}[-1] .= (" \n" x $blanklines)." $_\n";
		    }
		    $blanklines = 0;
		    $expect = 'more change data or trailer';
		    $entry->{ERROR} = [ $file, $NR, _g( "unrecognised line" ),
					"$_" ];
		};
	}
    }

    $expect eq 'next heading or eof'
	|| do {
	    $entry->{ERROR} = [ $file, $NR,
				sprintf(_g("found eof where expected %s"),
					$expect) ];
	    $self->_do_parse_error( @{$entry->{ERROR}} );
	};
    unless ($entry->is_empty) {
	$entry->{'Closes'} = find_closes( $entry->{Changes} );
	push @{$self->{data}}, $entry;
    }

    if ($self->{config}{infile}) {
	close $fh or do {
	    $self->_do_fatal_error( _g("can't close file %s: %s"),
				    $file, $!);
	    return undef;
	};
    }

#    use Data::Dumper;
#    print Dumper( $self );

    return $self;
}

1;
__END__

=head1 SEE ALSO

Dpkg::Changelog

Description of the Debian changelog format in the Debian policy:
L<http://www.debian.org/doc/debian-policy/ch-source.html#s-dpkgchangelog>.

=head1 AUTHOR

Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Frank Lichtenheld

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

=cut
