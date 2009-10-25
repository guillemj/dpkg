#
# Dpkg::Changelog::Debian
#
# Copyright © 1996 Ian Jackson
# Copyright © 2005 Frank Lichtenheld <frank@lichtenheld.de>
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

use Fcntl qw(:flock);
use English;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::Changelog qw(:util);
use base qw(Dpkg::Changelog);
use Dpkg::Changelog::Entry::Debian qw($regex_header $regex_trailer);

use constant {
    FIRST_HEADING => _g('first heading'),
    NEXT_OR_EOF => _g('next heading or eof'),
    START_CHANGES => _g('start of change data'),
    CHANGES_OR_TRAILER => _g('more change data or trailer'),
};

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

    my $expect = FIRST_HEADING;
    my $entry = Dpkg::Changelog::Entry::Debian->new();
    my @blanklines = ();
    my $unknowncounter = 1; # to make version unique, e.g. for using as id

    while (<$fh>) {
	chomp;
	if ($_ =~ $regex_header) {
	    (my $options = $4) =~ s/^\s+//;
	    unless ($expect eq FIRST_HEADING
		    || $expect eq NEXT_OR_EOF) {
		$self->_do_parse_error($file, $NR,
		    sprintf(_g("found start of entry where expected %s"),
		    $expect), "$_");
	    }
	    unless ($entry->is_empty) {
		push @{$self->{data}}, $entry;
		$entry = Dpkg::Changelog::Entry::Debian->new();
		last if $self->_abort_early;
	    }
	    $entry->set_part('header', $_);
	    foreach my $error ($entry->check_header()) {
		$self->_do_parse_error($file, $NR, $error, $_);
	    }
	    $expect= START_CHANGES;
	    @blanklines = ();
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
		 || m/^Changes for [\w.+-]+-[\w.+-]+:?\s*$/io
		 || m/^Old Changelog:\s*$/io
		 || m/^(?:\d+:)?\w[\w.+~-]*:?\s*$/o) {
	    # save entries on old changelog format verbatim
	    # we assume the rest of the file will be in old format once we
	    # hit it for the first time
	    $self->{oldformat} = "$_\n";
	    $self->{oldformat} .= join "", <$fh>;
	} elsif (m/^\S/) {
	    $self->_do_parse_error($file, $NR,
				  _g("badly formatted heading line"), "$_");
	} elsif ($_ =~ $regex_trailer) {
	    $expect eq CHANGES_OR_TRAILER ||
		$self->_do_parse_error($file, $NR,
				       sprintf(_g("found trailer where expected %s"),
					       $expect), "$_");
	    $entry->set_part("trailer", $_);
	    $entry->extend_part("blank_after_changes", [ @blanklines ]);
	    @blanklines = ();
	    foreach my $error ($entry->check_header()) {
		$self->_do_parse_error($file, $NR, $error, $_);
	    }
	    $expect = NEXT_OR_EOF;
	} elsif (m/^ \-\-/) {
	    $self->_do_parse_error($file, $NR,
				   _g( "badly formatted trailer line" ), "$_");
#	    $expect = NEXT_OR_EOF
#		if $expect eq CHANGES_OR_TRAILER;
	} elsif (m/^\s{2,}(\S)/) {
	    $expect eq START_CHANGES
		|| $expect eq CHANGES_OR_TRAILER
		|| do {
		    $self->_do_parse_error($file, $NR,
					   sprintf(_g("found change data where expected %s"),
						   $expect), "$_");
		    if (($expect eq NEXT_OR_EOF)
			&& !$entry->is_empty) {
			# lets assume we have missed the actual header line
			push @{$self->{data}}, $entry;
			$entry = Dpkg::Changelog::Entry::Debian->new();
			$entry->set_part('header', "unknown (unknown" . ($unknowncounter++) . ") unknown; urgency=unknown");
		    }
		};
	    # Keep raw changes
	    $entry->extend_part('changes', [ @blanklines, $_ ]);
	    @blanklines = ();
	    $expect = CHANGES_OR_TRAILER;
	} elsif (!m/\S/) {
	    if ($expect eq START_CHANGES) {
		$entry->extend_part("blank_after_header", $_);
		next;
	    } elsif ($expect eq NEXT_OR_EOF) {
		$entry->extend_part("blank_after_trailer", $_);
		next;
	    } elsif ($expect ne CHANGES_OR_TRAILER) {
		$self->_do_parse_error($file, $NR,
		      sprintf(_g("found blank line where expected %s"), $expect));
	    }
	    push @blanklines, $_;
	} else {
	    $self->_do_parse_error($file, $NR, _g( "unrecognised line" ),
				   "$_");
	    ($expect eq START_CHANGES
		|| $expect eq CHANGES_OR_TRAILER)
		&& do {
		    # lets assume change data if we expected it
		    $entry->extend_part("changes", [ @blanklines, $_]);
		    @blanklines = ();
		    $expect = CHANGES_OR_TRAILER;
		};
	}
    }

    $expect eq NEXT_OR_EOF
	|| do {
	    $self->_do_parse_error($file, $NR,
		sprintf(_g("found eof where expected %s"), $expect));
	};
    unless ($entry->is_empty) {
	push @{$self->{data}}, $entry;
    }

    if ($self->{config}{infile}) {
	close $fh or do {
	    $self->_do_fatal_error( _g("can't close file %s: %s"),
				    $file, $!);
	    return undef;
	};
    }

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
