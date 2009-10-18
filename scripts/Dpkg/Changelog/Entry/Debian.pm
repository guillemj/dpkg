# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Changelog::Entry::Debian;

use strict;
use warnings;

use Exporter;
use Dpkg::Changelog::Entry;
use base qw(Exporter Dpkg::Changelog::Entry);
our @EXPORT_OK = qw($regex_header $regex_trailer);

use Dpkg::Control::Changelog;
use Dpkg::Version;
use Dpkg::Changelog qw(:util);

=head1 NAME

Dpkg::Changelog::Entry::Debian - represents a Debian changelog entry

=head1 DESCRIPTION

This object represents a Debian changelog entry. It implements the
generic interface Dpkg::Changelog::Entry. Only functions specific to this
implementation are described below.

=head1 VARIABLES

$regex_header, $regex_trailer are two regular expressions that can be used
to match a line and know whether it's a valid header/trailer line.

The matched content for $regex_header is the source package name ($1), the
version ($2), the target distributions ($3) and the options on the rest
of the line ($4). For $regex_trailer, it's the maintainer name ($1), its
email ($2), some blanks ($3) and the timestamp ($4).

=cut

my $name_chars = qr/[-+0-9a-z.]/i;
our $regex_header = qr/^(\w$name_chars*) \(([^\(\) \t]+)\)((?:\s+$name_chars+)+)\;(.*)$/i;
our $regex_trailer = qr/^ \-\- (.*) <(.*)>(  ?)((\w+\,\s*)?\d{1,2}\s+\w+\s+\d{4}\s+\d{1,2}:\d\d:\d\d\s+[-+]\d{4}(\s+\([^\\\(\)]\))?)\s*$/o;

=head1 FUNCTIONS

=over 4

=item $entry->normalize()

Normalize the content. Strip whitespaces at end of lines, use a single
empty line to separate each part.

=cut

sub normalize {
    my ($self) = @_;
    $self->SUPER::normalize();
    #XXX: recreate header/trailer
}

sub get_source {
    my ($self) = @_;
    if (defined($self->{header}) and $self->{header} =~ $regex_header) {
	return $1;
    }
    return undef;
}

sub get_version {
    my ($self) = @_;
    if (defined($self->{header}) and $self->{header} =~ $regex_header) {
	return Dpkg::Version->new($2) || $2;
    }
    return undef;
}

sub get_distributions {
    my ($self) = @_;
    if (defined($self->{header}) and $self->{header} =~ $regex_header) {
	my $value = $3;
	$value =~ s/^\s+//;
	my @dists = split(/\s+/, $value);
	return @dists if wantarray;
	return $dists[0];
    }
    return () if wantarray;
    return undef;
}

sub get_optional_fields {
    my ($self) = @_;
    my $f = Dpkg::Control::Changelog->new();
    if (defined($self->{header}) and $self->{header} =~ $regex_header) {
	my $options = $4;
	$options =~ s/^\s+//;
	foreach my $opt (split(/\s*,\s*/, $options)) {
	    if ($opt =~ m/^([-0-9a-z]+)\=\s*(.*\S)$/i) {
		$f->{$1} = $2;
	    }
	}
    }
    my $closes = find_closes(join("\n", @{$self->{changes}}));
    if (@$closes) {
	$f->{Closes} = join(" ", @$closes);
    }
    return $f;
}

sub get_urgency {
    my ($self) = @_;
    my $f = $self->get_optional_fields();
    if (exists $f->{Urgency}) {
	$f->{Urgency} =~ s/\s.*$//;
	return lc($f->{Urgency});
    }
    return undef;
}

sub get_maintainer {
    my ($self) = @_;
    if (defined($self->{trailer}) and $self->{trailer} =~ $regex_trailer) {
	return "$1 <$2>";
    }
    return undef;
}

sub get_timestamp {
    my ($self) = @_;
    if (defined($self->{trailer}) and $self->{trailer} =~ $regex_trailer) {
	return $4;
    }
    return undef;
}

=back

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
