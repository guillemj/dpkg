#
# Dpkg::Changelog
#
# Copyright © 2005, 2007 Frank Lichtenheld <frank@lichtenheld.de>
# Copyright © 2009       Raphaël Hertzog <hertzog@debian.org>
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

FIXME: to be written

=head2 Functions

=cut

package Dpkg::Changelog;

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(:DEFAULT report);
use Dpkg::Control::Changelog;
use Dpkg::Control::Fields;
use Dpkg::Version;
use Dpkg::Vendor qw(run_vendor_hook);

use base qw(Exporter);

our %EXPORT_TAGS = ( 'util' => [ qw(
                data2rfc822
                data2rfc822_mult
                get_dpkg_changes
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
	    warning("%20s(l$.): $error\nLINE: $line", $file);
	} else {
	    warning("%20s(l$.): $error", $file);
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

    if (($$start || $$end) &&
        (length($$from) || length($$since) || length($$to) || length($$until)))
    {
	warning(_g( "you can't combine 'count' or 'offset' with any other range option" ));
	$$from = $$since = $$to = $$until = '';
    }
    if (length($$from) && length($$since)) {
	warning(_g( "you can only specify one of 'from' and 'since', using 'since'" ));
	$$from = '';
    }
    if (length($$to) && length($$until)) {
	warning(_g( "you can only specify one of 'to' and 'until', using 'until'" ));
	$$to = '';
    }
    $$start = 0 if $$start < 0;
    return if $$start > $#$data;
    $$end = $#$data if $$end > $#$data;
    return if $$end < 0;
    $$end = $$start if $$end < $$start;

    # Handle non-existing versions
    my (%versions, @versions);
    foreach my $entry (@{$data}) {
        $versions{$entry->get_version()->as_string()} = 1;
        push @versions, $entry->get_version()->as_string();
    }
    if ((length($$since) and not exists $versions{$$since})) {
        warning(_g("'%s' option specifies non-existing version"), "since");
        warning(_g("use newest entry that is smaller than the one specified"));
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_LT, $$since)) {
                $$since = $v;
                last;
            }
        }
        if (not exists $versions{$$since}) {
            # No version was smaller, include all
            warning(_g("none found, starting from the oldest entry"));
            $$since = '';
            $$from = $versions[-1];
        }
    }
    if ((length($$from) and not exists $versions{$$from})) {
        warning(_g("'%s' option specifies non-existing version"), "from");
        warning(_g("use oldest entry that is bigger than the one specified"));
        my $oldest;
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_GT, $$from)) {
                $oldest = $v;
            }
        }
        if (defined($oldest)) {
            $$from = $oldest;
        } else {
            warning(_g("no such entry found, ignoring '%s' parameter"), "from");
            $$from = ''; # No version was bigger
        }
    }
    if ((length($$until) and not exists $versions{$$until})) {
        warning(_g("'%s' option specifies non-existing version"), "until");
        warning(_g("use oldest entry that is bigger than the one specified"));
        my $oldest;
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_GT, $$until)) {
                $oldest = $v;
            }
        }
        if (defined($oldest)) {
            $$until = $oldest;
        } else {
            warning(_g("no such entry found, ignoring '%s' parameter"), "until");
            $$until = ''; # No version was bigger
        }
    }
    if ((length($$to) and not exists $versions{$$to})) {
        warning(_g("'%s' option specifies non-existing version"), "to");
        warning(_g("use newest entry that is smaller than the one specified"));
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_LT, $$to)) {
                $$to = $v;
                last;
            }
        }
        if (not exists $versions{$$to}) {
            # No version was smaller
            warning(_g("no such entry found, ignoring '%s' parameter"), "to");
            $$to = '';
        }
    }

    if (length($$since) && ($data->[0]->get_version() eq $$since)) {
	warning(_g( "'since' option specifies most recent version, ignoring" ));
	$$since = '';
    }
    if (length($$until) && ($data->[$#{$data}]->get_version() eq $$until)) {
	warning(_g( "'until' option specifies oldest version, ignoring" ));
	$$until = '';
    }
    return 1;
}

sub _data_range {
    my ($self, $config) = @_;

    my $data = $self->data or return undef;

    return [ @$data ] if $config->{all};

    my ($since, $until, $from, $to, $count, $offset) = ('', '', '', '', 0, 0);
    $since = $config->{since} if defined($config->{since});
    $until = $config->{until} if defined($config->{until});
    $from = $config->{from} if defined($config->{from});
    $to = $config->{to} if defined($config->{to});
    $count = $config->{count} if defined($config->{count});
    $offset = $config->{offset} if defined($config->{offset});

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


    unless (length($from) or length($to) or length($since) or length($until)
            or $start or $end)
    {
	return [ @$data ] if $config->{default_all} and not $count;
	return [ $data->[0] ];
    }

    return [ @{$data}[$start .. $end] ] if $start or $end;

    my @result;

    my $include = 1;
    $include = 0 if length($to) or length($until);
    foreach (@$data) {
	my $v = $_->get_version();
	$include = 1 if $to and $v eq $to;
	last if $since and $v eq $since;

	push @result, $_ if $include;

	$include = 1 if $until and $v eq $until;
	last if $from and $v eq $from;
    }

    return \@result if scalar(@result);
    return undef;
}

sub _abort_early {
    my ($self) = @_;

    my $data = $self->data or return;
    my $config = $self->{config} or return;

#    use Data::Dumper;
#    warn "Abort early? (\$# = $#$data)\n".Dumper($config);

    return if $config->{all};

    my ($since, $until, $from, $to, $count, $offset) = ('', '', '', '', 0, 0);
    $since = $config->{since} if defined($config->{since});
    $until = $config->{until} if defined($config->{until});
    $from = $config->{from} if defined($config->{from});
    $to = $config->{to} if defined($config->{to});
    $count = $config->{count} if defined($config->{count});
    $offset = $config->{offset} if defined($config->{offset});

    return if $offset and not $count;
    return if $offset < 0 or $count < 0;
    if ($offset > 0) {
	$offset -= ($count < 0);
    }
    my $start = my $end = $offset;
    $end += $count-1 if $count > 0;

    unless (length($from) or length($to) or length($since) or length($until)
            or $start or $end)
    {
	return if not $count;
	return 1 if @$data;
    }

    return 1 if ($start or $end)
	and $start < @$data and $end < @$data;

    return unless length($since) or length($from);
    foreach (@$data) {
	my $v = $_->get_version();

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

our ( @URGENCIES, %URGENCIES );
BEGIN {
    @URGENCIES = qw(low medium high critical emergency);
    my $i = 1;
    %URGENCIES = map { $_ => $i++ } @URGENCIES;
}

sub dpkg {
    my ($self, $config) = @_;

    $self->{config}{DPKG} = $config if $config;

    $config = $self->{config}{DPKG} || {};
    my $data = $self->_data_range( $config ) or return undef;

    my $f = Dpkg::Control::Changelog->new();
    $f->{Urgency} = $data->[0]->get_urgency() || "unknown";
    $f->{Source} = $data->[0]->get_source() || "unknown";
    $f->{Version} = $data->[0]->get_version() || "unknown";
    $f->{Distribution} = join(" ", $data->[0]->get_distributions());
    $f->{Maintainer} = $data->[0]->get_maintainer() || '';
    $f->{Date} = $data->[0]->get_timestamp() || '';
    $f->{Changes} = get_dpkg_changes($data->[0]);

    # handle optional fields
    my $opts = $data->[0]->get_optional_fields();
    my %closes;
    foreach (keys %$opts) {
	if (/^Urgency$/i) { # Already dealt
	} elsif (/^Closes$/i) {
	    $closes{$_} = 1 foreach (split(/\s+/, $opts->{Closes}));
	} else {
	    field_transfer_single($opts, $f);
	}
    }

    my $first = 1; my $urg_comment = '';
    foreach my $entry (@$data) {
	$first = 0, next if $first;

	my $oldurg = $f->{Urgency} || '';
	my $oldurgn = $URGENCIES{$f->{Urgency}} || -1;
	my $newurg = $entry->get_urgency() || '';
	my $newurgn = $URGENCIES{$newurg} || -1;
	$f->{Urgency} = ($newurgn > $oldurgn) ? $newurg : $oldurg;

	$f->{Changes} .= "\n ." . get_dpkg_changes($entry);

	# handle optional fields
	$opts = $entry->get_optional_fields();
	foreach (keys %$opts) {
	    if (/^Closes$/i) {
		$closes{$_} = 1 foreach (split(/\s+/, $opts->{Closes}));
	    } elsif (not exists $f->{$_}) { # Don't overwrite an existing field
		field_transfer_single($opts, $f);
	    }
	}
    }

    if (scalar keys %closes) {
	$f->{Closes} = join " ", sort { $a <=> $b } keys %closes;
    }
    run_vendor_hook("post-process-changelog-entry", $f);

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
	my $f = Dpkg::Control::Changelog->new();
	$f->{Urgency} = $entry->get_urgency() || "unknown";
	$f->{Source} = $entry->get_source() || "unknown";
	$f->{Version} = $entry->get_version() || "unknown";
	$f->{Distribution} = join(" ", $entry->get_distributions());
	$f->{Maintainer} = $entry->get_maintainer() || "";
	$f->{Date} = $entry->get_timestamp() || "";
	$f->{Changes} = get_dpkg_changes($entry);

	# handle optional fields
	my $opts = $entry->get_optional_fields();
	foreach (keys %$opts) {
	    field_transfer_single($opts, $f) unless exists $f->{$_};
	}

        run_vendor_hook("post-process-changelog-entry", $f);

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

The following options are also supported by all output methods but
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
    } elsif (ref($data)) {
	my $rfc822_str = $data->output;

	return $rfc822_str;
    } else {
	return;
    }
}

=pod

=head3 get_dpkg_changes

Takes a Dpkg::Changelog::Entry object as first argument.

Returns a string that is suitable for using it in a C<Changes> field
in the output format of C<dpkg-parsechangelog>.

=cut

sub get_dpkg_changes {
    my $entry = shift;
    my $header = $entry->get_part("header") || "";
    $header =~ s/\s+$//;
    my $changes = "\n $header\n .\n";
    foreach my $line (@{$entry->get_part("changes")}) {
	$line =~ s/\s+$//;
	if ($line eq "") {
	    $changes .= " .\n";
	} else {
	    $changes .= " $line\n";
	}
    }
    chomp $changes;
    return $changes;
}

1;
__END__

=head1 AUTHOR

Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2005, 2007 by Frank Lichtenheld
Copyright E<copy> 2009 by Raphael Hertzog

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
