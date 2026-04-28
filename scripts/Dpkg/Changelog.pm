# Copyright © 2005, 2007 Frank Lichtenheld <frank@lichtenheld.de>
# Copyright © 2009       Raphaël Hertzog <hertzog@debian.org>
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

=encoding utf8

=head1 NAME

Dpkg::Changelog - base class to implement a changelog parser

=head1 DESCRIPTION

Dpkg::Changelog is a class representing a changelog file
as an array of changelog entries (L<Dpkg::Changelog::Entry>).
By deriving this class and implementing its parse() method, you
add the ability to fill this object with changelog entries.

=cut

package Dpkg::Changelog 2.00;

use v5.36;

use Carp;

use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(:DEFAULT report REPORT_WARN);
use Dpkg::Control;
use Dpkg::Control::Changelog;
use Dpkg::Control::Fields;
use Dpkg::Index;
use Dpkg::Version;
use Dpkg::Vendor qw(run_vendor_hook);

use parent qw(Dpkg::Interface::Storable);

use overload
    '@{}' => sub { return $_[0]->{data} };

=head1 METHODS

=over 4

=item $chlog = Dpkg::Changelog->new(%opts)

Creates a new changelog object.

Accepts the same options as $chlog->set_options().

=cut

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;
    my $self = {
        verbose => 1,
        parse_errors => []
    };
    bless $self, $class;
    $self->set_options(%opts);
    return $self;
}

=item $chlog->set_options(%opts)

Change the value of some options.

Options:

=over

=item B<verbose>

Defines whether parse errors are displayed as warnings by default.

Defaults to 1.

=item B<reportfile>

A string to use instead of the name of the file parsed, in particular
in error messages.

=item B<range>

Defines the range of entries that we want to parse, the parser will stop as
soon as it has parsed enough data to satisfy $chlog->get_range($opts{range}).

=back

=cut

sub set_options {
    my ($self, %opts) = @_;
    $self->{$_} = $opts{$_} foreach keys %opts;
}

=item $count = $chlog->parse($fh, $description)

Read the filehandle and parse a changelog in it. The data in the object is
reset before parsing new data.

Returns the number of changelog entries that have been parsed with success.

This method needs to be implemented by one of the specialized changelog
format subclasses.

=item $count = $chlog->load($filename)

Parse $filename contents for a changelog.

Returns the number of changelog entries that have been parsed with success.

=item $chlog->reset_parse_errors()

Can be used to delete all information about errors occurred during
previous parse() runs.

=cut

sub reset_parse_errors {
    my $self = shift;
    $self->{parse_errors} = [];
}

=item $chlog->parse_error($file, $line_nr, $error, [$line])

Record a new parse error in $file at line $line_nr. The error message is
specified with $error and a copy of the line can be recorded in $line.

=cut

sub parse_error {
    my ($self, $file, $line_nr, $error, $line) = @_;

    push @{$self->{parse_errors}}, [ $file, $line_nr, $error, $line ];

    if ($self->{verbose}) {
        if ($line) {
            warning("%20s(l$line_nr): $error\nLINE: $line", $file);
        } else {
            warning("%20s(l$line_nr): $error", $file);
        }
    }
}

=item @errors = $chlog->get_parse_errors()

=item $errors = $chlog->get_parse_errors()

Returns all error messages from the last parse() run.
If called in scalar context returns a human readable
string representation. If called in list context returns
an array of arrays. Each of these arrays contains

=over 4

=item 1.

a string describing the origin of the data (a filename usually). If the
B<reportfile> configuration option was given, its value will be used instead.

=item 2.

the line number where the error occurred

=item 3.

an error description

=item 4.

the original line

=back

=cut

sub get_parse_errors {
    my $self = shift;

    if (wantarray) {
        return @{$self->{parse_errors}};
    } else {
        my $res = '';
        foreach my $e (@{$self->{parse_errors}}) {
            if ($e->[3]) {
                $res .= report(REPORT_WARN, g_("%s(l%s): %s\nLINE: %s"), @$e);
            } else {
                $res .= report(REPORT_WARN, g_('%s(l%s): %s'), @$e);
            }
        }
        return $res;
    }
}

=item $chlog->set_unparsed_tail($tail)

Add a string representing unparsed lines after the changelog entries.
Use undef as $tail to remove the unparsed lines currently set.

=item $string = $chlog->get_unparsed_tail()

Return a string representing the unparsed lines after the changelog
entries. Returns undef if there's no such thing.

=cut

sub set_unparsed_tail {
    my ($self, $tail) = @_;
    $self->{unparsed_tail} = $tail;
}

sub get_unparsed_tail {
    my $self = shift;
    return $self->{unparsed_tail};
}

=item @entries = @{$chlog}

Returns all the L<Dpkg::Changelog::Entry> objects contained in this changelog
in the order in which they have been parsed.

=item @entries = $chlog->get_range($range)

=item $entries = $chlog->get_range($range)

Returns an array (if called in list context) or a reference to an array of
L<Dpkg::Changelog::Entry> objects which each represent one entry of the
changelog. $range is a hash reference describing the range of entries
to return. See section L</RANGE SELECTION>.

=cut

sub _sanitize_range {
    my ($self, $r) = @_;
    my $data = $self->{data};

    if (defined($r->{offset}) and not defined($r->{count})) {
        warning(g_("'offset' without 'count' has no effect")) if $self->{verbose};
        delete $r->{offset};
    }

    ## no critic (ControlStructures::ProhibitUntilBlocks)
    if ((defined($r->{count}) || defined($r->{offset})) &&
        (defined($r->{from}) || defined($r->{since}) ||
         defined($r->{to}) || defined($r->{until})))
    {
        warning(g_("cannot combine 'count' or 'offset' with any other " .
                   'range option')) if $self->{verbose};
        delete $r->{from};
        delete $r->{since};
        delete $r->{to};
        delete $r->{until};
    }
    if (defined($r->{from}) && defined($r->{since})) {
        warning(g_("can only specify one of 'from' and 'since', using " .
                   "'since'")) if $self->{verbose};
        delete $r->{from};
    }
    if (defined($r->{to}) && defined($r->{until})) {
        warning(g_("can only specify one of 'to' and 'until', using " .
                   "'until'")) if $self->{verbose};
        delete $r->{to};
    }

    # Handle non-existing versions.
    my (%versions, @versions);
    foreach my $entry (@{$data}) {
        my $version = $entry->get_version();
        next unless defined $version;
        $versions{$version->as_string()} = 1;
        push @versions, $version->as_string();
    }
    if ((defined($r->{since}) and not exists $versions{$r->{since}})) {
        warning(g_("'%s' option specifies non-existing version '%s'"), 'since', $r->{since});
        warning(g_('use newest entry that is earlier than the one specified'));
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_LT, $r->{since})) {
                $r->{since} = $v;
                last;
            }
        }
        if (not exists $versions{$r->{since}}) {
            # No version was earlier, include all.
            warning(g_('none found, starting from the oldest entry'));
            delete $r->{since};
            $r->{from} = $versions[-1];
        }
    }
    if ((defined($r->{from}) and not exists $versions{$r->{from}})) {
        warning(g_("'%s' option specifies non-existing version '%s'"), 'from', $r->{from});
        warning(g_('use oldest entry that is later than the one specified'));
        my $oldest;
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_GT, $r->{from})) {
                $oldest = $v;
            }
        }
        if (defined($oldest)) {
            $r->{from} = $oldest;
        } else {
            # No version was oldest.
            warning(g_("no such entry found, ignoring '%s' parameter '%s'"), 'from', $r->{from});
            delete $r->{from};
        }
    }
    if (defined($r->{until}) and not exists $versions{$r->{until}}) {
        warning(g_("'%s' option specifies non-existing version '%s'"), 'until', $r->{until});
        warning(g_('use oldest entry that is later than the one specified'));
        my $oldest;
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_GT, $r->{until})) {
                $oldest = $v;
            }
        }
        if (defined($oldest)) {
            $r->{until} = $oldest;
        } else {
            # No version was oldest.
            warning(g_("no such entry found, ignoring '%s' parameter '%s'"), 'until', $r->{until});
            delete $r->{until};
        }
    }
    if (defined($r->{to}) and not exists $versions{$r->{to}}) {
        warning(g_("'%s' option specifies non-existing version '%s'"), 'to', $r->{to});
        warning(g_('use newest entry that is earlier than the one specified'));
        foreach my $v (@versions) {
            if (version_compare_relation($v, REL_LT, $r->{to})) {
                $r->{to} = $v;
                last;
            }
        }
        if (not exists $versions{$r->{to}}) {
            # No version was earlier.
            warning(g_("no such entry found, ignoring '%s' parameter '%s'"), 'to', $r->{to});
            delete $r->{to};
        }
    }

    if (defined($r->{since}) and $data->[0]->get_version() eq $r->{since}) {
        warning(g_("'since' option specifies most recent version '%s', ignoring"), $r->{since});
        delete $r->{since};
    }
    if (defined($r->{until}) and $data->[-1]->get_version() eq $r->{until}) {
        warning(g_("'until' option specifies oldest version '%s', ignoring"), $r->{until});
        delete $r->{until};
    }
    ## use critic
}

sub get_range {
    my ($self, $range) = @_;
    $range //= {};
    my $res = $self->_data_range($range);
    return unless defined $res;
    if (wantarray) {
        return reverse @{$res} if $range->{reverse};
        return @{$res};
    } else {
        return $res;
    }
}

sub _is_full_range {
    my ($self, $range) = @_;

    return 1 if $range->{all};

    # If no range delimiter is specified, we want everything.
    foreach my $delim (qw(since until from to count offset)) {
        return 0 if exists $range->{$delim};
    }

    return 1;
}

sub _data_range {
    my ($self, $range) = @_;

    my $data = $self->{data} or return;

    return [ @$data ] if $self->_is_full_range($range);

    $self->_sanitize_range($range);

    my ($start, $end);
    if (defined($range->{count})) {
        my $offset = $range->{offset} // 0;
        my $count = $range->{count};
        # Convert count/offset in start/end.
        if ($offset > 0) {
            $offset -= ($count < 0);
        } elsif ($offset < 0) {
            $offset = $#$data + ($count > 0) + $offset;
        } else {
            $offset = $#$data if $count < 0;
        }
        $start = $end = $offset;
        $start += $count + 1 if $count < 0;
        $end += $count - 1 if $count > 0;
        # Check limits.
        $start = 0 if $start < 0;
        return if $start > $#$data;
        $end = $#$data if $end > $#$data;
        return if $end < 0;
        $end = $start if $end < $start;
        return [ @{$data}[$start .. $end] ];
    }

    ## no critic (ControlStructures::ProhibitUntilBlocks)
    my @result;
    my $include = 1;
    $include = 0 if defined($range->{to}) or defined($range->{until});
    foreach my $entry (@{$data}) {
        my $v = $entry->get_version();
        $include = 1 if defined($range->{to}) and $v eq $range->{to};
        last if defined($range->{since}) and $v eq $range->{since};

        push @result, $entry if $include;

        $include = 1 if defined($range->{until}) and $v eq $range->{until};
        last if defined($range->{from}) and $v eq $range->{from};
    }
    ## use critic

    return \@result if scalar(@result);
    return;
}

=item $bool = $chlog->abort_early()

Returns true if enough data have been parsed to be able to return all
entries selected by the range set at creation (or with set_options).

=cut

sub abort_early {
    my $self = shift;

    my $data = $self->{data} or return;
    my $r = $self->{range} or return;
    my $count = $r->{count} // 0;
    my $offset = $r->{offset} // 0;

    return if $self->_is_full_range($r);
    return if $offset < 0 or $count < 0;
    if (defined($r->{count})) {
        if ($offset > 0) {
            $offset -= ($count < 0);
        }
        my $start = my $end = $offset;
        $end += $count-1 if $count > 0;
        return $start < @{$data} > $end;
    }

    return unless defined($r->{since}) or defined($r->{from});
    foreach my $entry (@{$data}) {
        my $v = $entry->get_version();
        return 1 if defined($r->{since}) and $v eq $r->{since};
        return 1 if defined($r->{from}) and $v eq $r->{from};
    }

    return;
}

=item $string = "$chlog"

=item $string = $chlog->output()

Returns a string representation of the changelog (it's a concatenation of
the string representation of the individual changelog entries).

=item $string = $chlog->output($fh)

Output the changelog to the given filehandle.

=cut

sub output {
    my ($self, $fh) = @_;
    my $str = '';
    foreach my $entry (@{$self}) {
        my $text = $entry->output();
        print { $fh } $text if defined $fh;
        $str .= $text if defined wantarray;
    }
    my $text = $self->get_unparsed_tail();
    if (defined $text) {
        print { $fh } $text if defined $fh;
        $str .= $text if defined wantarray;
    }
    return $str;
}

=item $chlog->save($filename)

Save the changelog in the given file.

=cut

our (@URGENCIES, %URGENCIES);
BEGIN {
    @URGENCIES = qw(
        low
        medium
        high
        critical
        emergency
    );
    my $i = 1;
    %URGENCIES = map { $_ => $i++ } @URGENCIES;
}

sub _format_dpkg {
    my ($self, $range) = @_;

    my @data = $self->get_range($range) or return;
    my $src = shift @data;

    my $chlog = Dpkg::Control::Changelog->new();
    $chlog->{Urgency} = $src->get_urgency() || 'unknown';
    $chlog->{Source} = $src->get_source() || 'unknown';
    $chlog->{Version} = $src->get_version() // 'unknown';
    $chlog->{Distribution} = join ' ', $src->get_distributions();
    $chlog->{Maintainer} = $src->get_maintainer() // '';
    $chlog->{Date} = $src->get_timestamp() // '';
    $chlog->{Timestamp} = $src->get_timepiece ? $src->get_timepiece->epoch : '';
    $chlog->{Changes} = $src->get_dpkg_changes();

    # Handle optional fields.
    my $opts = $src->get_optional_fields();
    my %closes;
    foreach my $f (keys %{$opts}) {
        if ($f eq 'Urgency') {
            # Already handled.
        } elsif ($f eq 'Closes') {
            $closes{$_} = 1 foreach (split(/\s+/, $opts->{Closes}));
        } else {
            field_transfer_single($opts, $chlog, $f);
        }
    }

    foreach my $bin (@data) {
        my $oldurg = $chlog->{Urgency} // '';
        my $oldurgn = $URGENCIES{$chlog->{Urgency}} // -1;
        my $newurg = $bin->get_urgency() // '';
        my $newurgn = $URGENCIES{$newurg} // -1;
        $chlog->{Urgency} = ($newurgn > $oldurgn) ? $newurg : $oldurg;
        $chlog->{Changes} .= "\n" . $bin->get_dpkg_changes();

        # Handle optional fields.
        $opts = $bin->get_optional_fields();
        foreach my $f (keys %{$opts}) {
            if ($f eq 'Closes') {
                $closes{$_} = 1 foreach (split(/\s+/, $opts->{Closes}));
            } elsif (not exists $chlog->{$f}) {
                # Do not overwrite an existing field.
                field_transfer_single($opts, $chlog, $f);
            }
        }
    }

    if (scalar keys %closes) {
        $chlog->{Closes} = join ' ', sort { $a <=> $b } keys %closes;
    }
    run_vendor_hook('post-process-changelog-entry', $chlog);

    return $chlog;
}

sub _format_rfc822 {
    my ($self, $range) = @_;

    my @data = $self->get_range($range) or return;
    my @ctrl;

    foreach my $entry (@data) {
        my $chlog = Dpkg::Control::Changelog->new();
        $chlog->{Urgency} = $entry->get_urgency() || 'unknown';
        $chlog->{Source} = $entry->get_source() || 'unknown';
        $chlog->{Version} = $entry->get_version() // 'unknown';
        $chlog->{Distribution} = join ' ', $entry->get_distributions();
        $chlog->{Maintainer} = $entry->get_maintainer() // '';
        $chlog->{Date} = $entry->get_timestamp() // '';
        $chlog->{Timestamp} = $entry->get_timepiece ? $entry->get_timepiece->epoch : '';
        $chlog->{Changes} = $entry->get_dpkg_changes();

        # Handle optional fields.
        my $opts = $entry->get_optional_fields();
        foreach my $f (keys %{$opts}) {
            field_transfer_single($opts, $chlog, $f) unless exists $chlog->{$f};
        }

        run_vendor_hook('post-process-changelog-entry', $chlog);

        push @ctrl, $chlog;
    }

    return @ctrl;
}

=item $ctrl_index = $chlog->format_range($format, $range)

=item @ctrl_list = $chlog->format_range($format, $range)

Formats the changelog into L<Dpkg::Control::Changelog> objects representing
the entries selected by the optional range specifier (see L</RANGE SELECTION>
for details). In scalar context returns a L<Dpkg::Index> object containing
the selected entries, in list context returns an array of
L<Dpkg::Control::Changelog> objects.

With format B<dpkg> the returned L<Dpkg::Control::Changelog> object is
coalesced from the entries in the changelog that are part of the range
requested, with the fields described below, but considering that
"selected entry" means the first entry of the selected range.

With format B<rfc822> each returned L<Dpkg::Control::Changelog> objects
represents one entry in the changelog that is part of the range requested,
with the fields described below, but considering that "selected entry"
means for each entry.

The different formats return undef if no entries are matched. The following
fields are contained in the object(s) returned:

=over 4

=item Source

package name (selected entry)

=item Version

packages' version (selected entry)

=item Distribution

target distribution (selected entry)

=item Urgency

urgency (highest of all entries in range)

=item Maintainer

person that created the (selected) entry

=item Date

date of the (selected) entry

=item Timestamp

date of the (selected) entry as a timestamp in seconds since the epoch

=item Closes

bugs closed by the (selected) entry/entries, sorted by bug number

=item Changes

content of the (selected) entry/entries

=back

=cut

sub format_range {
    my ($self, $format, $range) = @_;

    my @ctrl;

    if ($format eq 'dpkg') {
        @ctrl = $self->_format_dpkg($range);
    } elsif ($format eq 'rfc822') {
        @ctrl = $self->_format_rfc822($range);
    } else {
        croak "unknown changelog output format $format";
    }

    if (wantarray) {
        return @ctrl;
    } else {
        my $index = Dpkg::Index->new(type => CTRL_CHANGELOG);

        foreach my $ctrl (@ctrl) {
            $index->add($ctrl);
        }

        return $index;
    }
}

=back

=head1 RANGE SELECTION

A range selection is described by a hash reference where
the allowed keys and values are described below.

The following options take a version number as value.

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

The following options don't take version numbers as values:

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

  Range                        Included entries
  -----                        ----------------
  since => '2.0'               3.1, 3.0, 2.2
  until => '2.0'               1.3, 1.2
  from  => '2.0'               3.1, 3.0, 2.2, 2.1, 2.0
  to    => '2.0'               2.0, 1.3, 1.2
  count =>  2                  3.1, 3.0
  count => -2                  1.3, 1.2
  count =>  3, offset => 2     2.2, 2.1, 2.0
  count =>  2, offset => -3    2.0, 1.3
  count => -2, offset => 3     3.0, 2.2
  count => -2, offset => -3    2.2, 2.1

Any combination of one option of C<since> and C<from> and one of
C<until> and C<to> returns the intersection of the two results
with only one of the options specified.

=head1 CHANGES

=head2 Version 2.00 (dpkg 1.20.0)

Remove methods: $chlog->dpkg(), $chlog->rfc822().

=head2 Version 1.01 (dpkg 1.18.8)

New method: $chlog->format_range().

Deprecated methods: $chlog->dpkg(), $chlog->rfc822().

New field Timestamp in output formats.

=head2 Version 1.00 (dpkg 1.15.6)

Mark the module as public.

=cut
1;
