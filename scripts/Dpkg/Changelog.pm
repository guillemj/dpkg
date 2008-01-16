#
# Dpkg::Changelog
#
# Copyright © 2005, 2007 Frank Lichtenheld <frank@lichtenheld.de>
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

Dpkg::Changelog

=head1 DESCRIPTION

to be written

=head2 Functions

=cut

package Dpkg::Changelog;

use strict;
use warnings;

use English;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning report syserr subprocerr);
use Dpkg::Cdata;
use Dpkg::Fields;

use base qw(Exporter);

our %EXPORT_TAGS = ( 'util' => [ qw(
                find_closes
                data2rfc822
                data2rfc822_mult
                get_dpkg_changes
		parse_changelog
) ] );
our @EXPORT_OK = @{$EXPORT_TAGS{util}};

=pod

=head3 init

Creates a new object instance. Takes a reference to a hash as
optional argument, which is interpreted as configuration options.
There are currently no supported general configuration options, but
see the other methods for more specific configuration options which
can also specified to C<init>.

If C<infile>, C<inhandle>, or C<instring> are specified, C<parse()>
is called from C<init>. If a fatal error is encountered during parsing
(e.g. the file can't be opened), C<init> will not return a
valid object but C<undef>!

=cut

sub init {
    my $classname = shift;
    my $config = shift || {};
    my $self = {};
    bless( $self, $classname );

    $config->{verbose} = 1 if $config->{debug};
    $self->{config} = $config;

    $self->reset_parse_errors;

    if ($self->{config}{infile}
	|| $self->{config}{inhandle}
	|| $self->{config}{instring}) {
	defined($self->parse) or return undef;
    }

    return $self;
}

=pod

=head3 reset_parse_errors

Can be used to delete all information about errors ocurred during
previous L<parse> runs. Note that C<parse()> also calls this method.

=cut

sub reset_parse_errors {
    my ($self) = @_;

    $self->{errors}{parser} = [];
}

sub _do_parse_error {
    my ($self, $file, $line_nr, $error, $line) = @_;
    shift;

    push @{$self->{errors}{parser}}, [ @_ ];

    unless ($self->{config}{quiet}) {
	if ($line) {
	    warning("%20s(l$NR): $error\nLINE: $line", $file);
	} else {
	    warning("%20s(l$NR): $error", $file);
	}
    }
}

=pod

=head3 get_parse_errors

Returns all error messages from the last L<parse> run.
If called in scalar context returns a human readable
string representation. If called in list context returns
an array of arrays. Each of these arrays contains

=over 4

=item 1.

the filename of the parsed file or C<FileHandle> or C<String>
if the input came from a file handle or a string. If the
reportfile configuration option was given, its value will be
used instead

=item 2.

the line number where the error occurred

=item 3.

an error description

=item 4.

the original line

=back

NOTE: This format isn't stable yet and may change in later versions
of this module.

=cut

sub get_parse_errors {
    my ($self) = @_;

    if (wantarray) {
	return @{$self->{errors}{parser}};
    } else {
	my $res = "";
	foreach my $e (@{$self->{errors}{parser}}) {
	    if ($e->[3]) {
		$res .= report(_g('warning'),_g("%s(l%s): %s\nLINE: %s"), @$e );
	    } else {
		$res .= report(_g('warning'),_g("%s(l%s): %s"), @$e );
	    }
	}
	return $res;
    }
}

sub _do_fatal_error {
    my ($self, $msg, @msg) = @_;

    $self->{errors}{fatal} = report(_g('fatal error'), $msg, @msg);
    warning($msg, @msg) unless $self->{config}{quiet};
}

=pod

=head3 get_error

Get the last non-parser error (e.g. the file to parse couldn't be opened).

=cut

sub get_error {
    my ($self) = @_;

    return $self->{errors}{fatal};
}

=pod

=head3 data

C<data> returns an array (if called in list context) or a reference
to an array of Dpkg::Changelog::Entry objects which each
represent one entry of the changelog.

This method supports the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=cut

sub data {
    my ($self, $config) = @_;

    my $data = $self->{data};
    if ($config) {
	$self->{config}{DATA} = $config if $config;
	$data = $self->_data_range( $config ) or return undef;
    }
    return @$data if wantarray;
    return $data;
}

sub __sanity_check_range {
    my ( $data, $from, $to, $since, $until, $start, $end ) = @_;

    if (($$start || $$end) && ($$from || $$since || $$to || $$until)) {
	warning(_g( "you can't combine 'count' or 'offset' with any other range option" ));
	$$from = $$since = $$to = $$until = '';
    }
    if ($$from && $$since) {
	warning(_g( "you can only specify one of 'from' and 'since', using 'since'" ));
	$$from = '';
    }
    if ($$to && $$until) {
	warning(_g( "you can only specify one of 'to' and 'until', using 'until'" ));
	$$to = '';
    }
    if ($$since && ($data->[0]{Version} eq $$since)) {
	warning(_g( "'since' option specifies most recent version, ignoring" ));
	$$since = '';
    }
    if ($$until && ($data->[$#{$data}]{Version} eq $$until)) {
	warning(_g( "'until' option specifies oldest version, ignoring" ));
	$$until = '';
    }
    $$start = 0 if $$start < 0;
    return if $$start > $#$data;
    $$end = $#$data if $$end > $#$data;
    return if $$end < 0;
    $$end = $$start if $$end < $$start;
    #TODO: compare versions
    return 1;
}

sub _data_range {
    my ($self, $config) = @_;

    my $data = $self->data or return undef;

    return [ @$data ] if $config->{all};

    my $since = $config->{since} || '';
    my $until = $config->{until} || '';
    my $from = $config->{from} || '';
    my $to = $config->{to} || '';
    my $count = $config->{count} || 0;
    my $offset = $config->{offset} || 0;

    return if $offset and not $count;
    if ($offset > 0) {
	$offset -= ($count < 0);
    } elsif ($offset < 0) {
	$offset = $#$data + ($count > 0) + $offset;
    } else {
	$offset = $#$data if $count < 0;
    }
    my $start = my $end = $offset;
    $start += $count+1 if $count < 0;
    $end += $count-1 if $count > 0;

    return unless __sanity_check_range( $data, \$from, \$to,
					\$since, \$until,
					\$start, \$end );


    unless ($from or $to or $since or $until or $start or $end) {
	return [ @$data ] if $config->{default_all} and not $count;
	return [ $data->[0] ];
    }

    return [ @{$data}[$start .. $end] ] if $start or $end;

    my @result;

    my $include = 1;
    $include = 0 if $to or $until;
    foreach (@$data) {
	my $v = $_->{Version};
	$include = 1 if $v eq $to;
	last if $v eq $since;

	push @result, $_ if $include;

	$include = 1 if $v eq $until;
	last if $v eq $from;
    }

    return \@result;
}

sub _abort_early {
    my ($self) = @_;

    my $data = $self->data or return;
    my $config = $self->{config} or return;

#    use Data::Dumper;
#    warn "Abort early? (\$# = $#$data)\n".Dumper($config);

    return if $config->{all};

    my $since = $config->{since} || '';
    my $until = $config->{until} || '';
    my $from = $config->{from} || '';
    my $to = $config->{to} || '';
    my $count = $config->{count} || 0;
    my $offset = $config->{offset} || 0;

    return if $offset and not $count;
    return if $offset < 0 or $count < 0;
    if ($offset > 0) {
	$offset -= ($count < 0);
    }
    my $start = my $end = $offset;
    $end += $count-1 if $count > 0;

    unless ($from or $to or $since or $until or $start or $end) {
	return if not $count;
	return 1 if @$data;
    }

    return 1 if ($start or $end)
	and $start < @$data and $end < @$data;

    return unless $since or $from;
    foreach (@$data) {
	my $v = $_->{Version};

	return 1 if $v eq $since;
	return 1 if $v eq $from;
    }

    return;
}

=pod

=head3 dpkg

(and B<dpkg_str>)

C<dpkg> returns a hash (in list context) or a hash reference
(in scalar context) where the keys are field names and the values are
field values. The following fields are given:

=over 4

=item Source

package name (in the first entry)

=item Version

packages' version (from first entry)

=item Distribution

target distribution (from first entry)

=item Urgency

urgency (highest of all printed entries)

=item Maintainer

person that created the (first) entry

=item Date

date of the (first) entry

=item Closes

bugs closed by the entry/entries, sorted by bug number

=item Changes

content of the the entry/entries

=back

C<dpkg_str> returns a stringified version of this hash. The fields are
ordered like in the list above.

Both methods support the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=head3 dpkg_str

See L<dpkg>.

=cut

our ( @CHANGELOG_FIELDS, %CHANGELOG_FIELDS );
our ( @URGENCIES, %URGENCIES );
BEGIN {
    @CHANGELOG_FIELDS = qw(Source Version Distribution
                           Urgency Maintainer Date Closes Changes
                           Timestamp Header Items Trailer
                           Urgency_comment Urgency_lc);
    tie %CHANGELOG_FIELDS, 'Dpkg::Fields::Object';
    %CHANGELOG_FIELDS = map { $_ => 1 } @CHANGELOG_FIELDS;
    @URGENCIES = qw(low medium high critical emergency);
    my $i = 1;
    %URGENCIES = map { $_ => $i++ } @URGENCIES;
}

sub dpkg {
    my ($self, $config) = @_;

    $self->{config}{DPKG} = $config if $config;

    $config = $self->{config}{DPKG} || {};
    my $data = $self->_data_range( $config ) or return undef;

    my $f = new Dpkg::Changelog::Entry;
    foreach my $field (qw( Urgency Source Version
			   Distribution Maintainer Date )) {
	$f->{$field} = $data->[0]{$field};
    }
    # handle unknown fields
    foreach my $field (keys %{$data->[0]}) {
	next if $CHANGELOG_FIELDS{$field};
	$f->{$field} = $data->[0]{$field};
    }

    $f->{Changes} = get_dpkg_changes( $data->[0] );
    $f->{Closes} = [ @{$data->[0]{Closes}} ];

    my $first = 1; my $urg_comment = '';
    foreach my $entry (@$data) {
	$first = 0, next if $first;

	my $oldurg = $f->{Urgency} || '';
	my $oldurgn = $URGENCIES{$f->{Urgency}} || -1;
	my $newurg = $entry->{Urgency_lc} || '';
	my $newurgn = $URGENCIES{$entry->{Urgency_lc}} || -1;
	$f->{Urgency} = ($newurgn > $oldurgn) ? $newurg : $oldurg;
	$urg_comment .= $entry->{Urgency_comment};

	$f->{Changes} .= "\n .".get_dpkg_changes( $entry );
	push @{$f->{Closes}}, @{$entry->{Closes}};

	# handle unknown fields
	foreach my $field (keys %$entry) {
	    next if $CHANGELOG_FIELDS{$field};
	    next if exists $f->{$field};
	    $f->{$field} = $entry->{$field};
	}
    }

    $f->{Closes} = join " ", sort { $a <=> $b } @{$f->{Closes}};
    $f->{Urgency} .= $urg_comment;

    return %$f if wantarray;
    return $f;
}

sub dpkg_str {
    return data2rfc822(scalar dpkg(@_));
}

=pod

=head3 rfc822

(and B<rfc822_str>)

C<rfc822> returns an array of hashes (in list context) or a reference
to this array (in scalar context) where each hash represents one entry
in the changelog. For the format of such a hash see the description
of the L<"dpkg"> method (while ignoring the remarks about which
values are taken from the first entry).

C<rfc822_str> returns a stringified version of this array.

Both methods support the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=head3 rfc822_str

See L<rfc822>.

=cut

sub rfc822 {
    my ($self, $config) = @_;

    $self->{config}{RFC822} = $config if $config;

    $config = $self->{config}{RFC822} || {};
    my $data = $self->_data_range( $config ) or return undef;
    my @out_data;

    foreach my $entry (@$data) {
	my $f = new Dpkg::Changelog::Entry;
	foreach my $field (qw( Urgency Source Version
			       Distribution Maintainer Date )) {
	    $f->{$field} = $entry->{$field};
	}

	$f->{Urgency} .= $entry->{Urgency_Comment};
	$f->{Changes} = get_dpkg_changes( $entry );
	$f->{Closes} = join " ", sort { $a <=> $b } @{$entry->{Closes}};

	# handle unknown fields
	foreach my $field (keys %$entry) {
	    next if $CHANGELOG_FIELDS{$field};
	    $f->{$field} = $entry->{$field};
	}

	push @out_data, $f;
    }

    return @out_data if wantarray;
    return \@out_data;
}

sub rfc822_str {
    return data2rfc822(scalar rfc822(@_));
}

=pod

=head1 COMMON OUTPUT OPTIONS

The following options are supported by all output methods,
all take a version number as value:

=over 4

=item since

Causes changelog information from all versions strictly
later than B<version> to be used.

=item until

Causes changelog information from all versions strictly
earlier than B<version> to be used.

=item from

Similar to C<since> but also includes the information for the
specified B<version> itself.

=item to

Similar to C<until> but also includes the information for the
specified B<version> itself.

=back

The following options also supported by all output methods but
don't take version numbers as values:

=over 4

=item all

If set to a true value, all entries of the changelog are returned,
this overrides all other options.

=item count

Expects a signed integer as value. Returns C<value> entries from the
top of the changelog if set to a positive integer, and C<abs(value)>
entries from the tail if set to a negative integer.

=item offset

Expects a signed integer as value. Changes the starting point for
C<count>, either counted from the top (positive integer) or from
the tail (negative integer). C<offset> has no effect if C<count>
wasn't given as well.

=back

Some examples for the above options. Imagine an example changelog with
entries for the versions 1.2, 1.3, 2.0, 2.1, 2.2, 3.0 and 3.1.

            Call                               Included entries
 C<E<lt>formatE<gt>({ since =E<gt> '2.0' })>  3.1, 3.0, 2.2
 C<E<lt>formatE<gt>({ until =E<gt> '2.0' })>  1.3, 1.2
 C<E<lt>formatE<gt>({ from =E<gt> '2.0' })>   3.1, 3.0, 2.2, 2.1, 2.0
 C<E<lt>formatE<gt>({ to =E<gt> '2.0' })>     2.0, 1.3, 1.2
 C<E<lt>formatE<gt>({ count =E<gt> 2 }>>      3.1, 3.0
 C<E<lt>formatE<gt>({ count =E<gt> -2 }>>     1.3, 1.2
 C<E<lt>formatE<gt>({ count =E<gt> 3,
		      offset=E<gt> 2 }>>      2.2, 2.1, 2.0
 C<E<lt>formatE<gt>({ count =E<gt> 2,
		      offset=E<gt> -3 }>>     2.0, 1.3
 C<E<lt>formatE<gt>({ count =E<gt> -2,
		      offset=E<gt> 3 }>>      3.0, 2.2
 C<E<lt>formatE<gt>({ count =E<gt> -2,
		      offset=E<gt> -3 }>>     2.2, 2.1

Any combination of one option of C<since> and C<from> and one of
C<until> and C<to> returns the intersection of the two results
with only one of the options specified.

=head1 UTILITY FUNCTIONS

=head3 find_closes

Takes one string as argument and finds "Closes: #123456, #654321" statements
as supported by the Debian Archive software in it. Returns all closed bug
numbers in an array reference.

=cut

sub find_closes {
    my $changes = shift;
    my @closes = ();

    while ($changes &&
	   ($changes =~ /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/ig)) {
	push(@closes, $& =~ /\#?\s?(\d+)/g);
    }

    @closes = sort { $a <=> $b } @closes;
    return \@closes;
}

=pod

=head3 data2rfc822

Takes a single argument, either a Dpkg::Changelog::Entry object
or a reference to an array of such objects.

Returns the data in RFC822 format as string.

=cut

sub data2rfc822 {
    my ($data) = @_;

    if (ref($data) eq "ARRAY") {
	my @rfc822 = ();

	foreach my $entry (@$data) {
	    push @rfc822, data2rfc822($entry);
	}

	return join "\n", @rfc822;
    } else {
	my $rfc822_str = $data->output;

	return $rfc822_str;
    }
}

=pod

=head3 get_dpkg_changes

Takes a Dpkg::Changelog::Entry object as first argument.

Returns a string that is suitable for using it in a C<Changes> field
in the output format of C<dpkg-parsechangelog>.

=cut

sub get_dpkg_changes {
    my $changes = "\n ".($_[0]->{Header}||'')."\n .\n".($_[0]->{Changes}||'');
    chomp $changes;
    $changes =~ s/^ $/ ./mgo;
    return $changes;
}

=pod

=head3 parse_changelog($file, $format, $since)

Calls "dpkg-parsechangelog -l$file -F$format -v$since"  and returns a
Dpkg::Fields::Object with the values output by the program.

=cut
sub parse_changelog {
    my ($changelogfile, $changelogformat, $since) = @_;

    my @exec = ('dpkg-parsechangelog');
    push(@exec, "-l$changelogfile");
    push(@exec, "-F$changelogformat") if defined($changelogformat);
    push(@exec, "-v$since") if defined($since);

    open(PARSECH, "-|", @exec) || syserr(_g("fork for parse changelog"));
    my $fields = parsecdata(\*PARSECH, _g("parsed version of changelog"));
    close(PARSECH) || subprocerr(_g("parse changelog"));
    return $fields;
}

=head1 NAME

Dpkg::Changelog::Entry - represents one entry in a Debian changelog

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

package Dpkg::Changelog::Entry;

sub new {
    my ($classname) = @_;

    tie my %entry, 'Dpkg::Fields::Object';
    tied(%entry)->set_field_importance(@CHANGELOG_FIELDS);
    my $entry = \%entry;
    bless $entry, $classname;
}

sub is_empty {
    my ($self) = @_;

    return !($self->{Changes}
	     || $self->{Source}
	     || $self->{Version}
	     || $self->{Maintainer}
	     || $self->{Date});
}

sub output {
    my $self = shift;
    return tied(%$self)->output(@_);
}

1;
__END__

=head1 AUTHOR

Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2005, 2007 by Frank Lichtenheld

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
