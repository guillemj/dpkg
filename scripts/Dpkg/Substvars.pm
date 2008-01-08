# Copyright 2007 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Substvars;

use strict;
use warnings;

use Dpkg qw($version);
use Dpkg::Arch qw(get_host_arch);
use Dpkg::ErrorHandling qw(error warning);
use Dpkg::Gettext;

use POSIX qw(:errno_h);
use English;

my $maxsubsts = 50;

=head1 NAME

Dpkg::Substvars - handle variable substitution in strings

=head1 DESCRIPTION

It provides some an object which is able to substitute variables in
strings.

=head1 METHODS

=over 8

=item my $s = Dpkg::Substvars->new($file)

Create a new object that can do substitutions. By default it contains
generic substitutions like ${Newline}, ${Space}, ${Tab}, ${dpkg:Version},
${dpkg:Upstream-Version} and ${Arch}.

Additional substitutions will be read from the $file passed as parameter.

=cut
sub new {
    my ($this, $arg) = @_;
    my $class = ref($this) || $this;
    my $self = {
	"Newline" => "\n",
	"Space" => " ",
	"Tab" => "\t",
	"dpkg:Version" => $version,
	"dpkg:Upstream-Version" => $version,
	"Arch" => get_host_arch(),
    };
    $self->{'dpkg:Upstream-Version'} =~ s/-[^-]+$//;
    bless $self, $class;
    if ($arg) {
        $self->parse($arg);
    }
    return $self;
}

=item $s->set($key, $value)

Add/replace a substitution.

=cut
sub set {
    my ($self, $key, $value) = @_;
    $self->{$key} = $value;
}

=item $s->get($key)

Get the value of a given substitution.

=cut
sub get {
    my ($self, $key) = @_;
    return $self->{$key};
}

=item $s->delete($key)

Remove a given substitution.

=cut
sub delete {
    my ($self, $key) = @_;
    return delete $self->{$key};
}

=item $s->parse($file)

Add new substitutions read from $file.

=cut
sub parse {
    my ($self, $varlistfile) = @_;
    $varlistfile="./$varlistfile" if $varlistfile =~ m/\s/;
    if (open(SV, "<", $varlistfile)) {
	binmode(SV);
	while (<SV>) {
	    next if m/^\#/ || !m/\S/;
	    s/\s*\n$//;
	    m/^(\w[-:0-9A-Za-z]*)\=/ ||
		error(_g("bad line in substvars file %s at line %d"),
		      $varlistfile, $.);
	    $self->{$1} = $';
	}
	close(SV);
    } elsif ($! != ENOENT ) {
	error(_g("unable to open substvars file %s: %s"), $varlistfile, $!);
    }
}

=item $s->set_version_substvars($version)

Defines ${binary:Version}, ${source:Version} and
${source:Upstream-Version} based on the given version string.

=cut
sub set_version_substvars {
    my ($self, $version) = @_;

    $self->{'binary:Version'} = $version;
    $self->{'source:Version'} = $version;
    $self->{'source:Version'} =~ s/\+b[0-9]+$//;
    $self->{'source:Upstream-Version'} = $version;
    $self->{'source:Upstream-Version'} =~ s/-[^-]*$//;

    # XXX: Source-Version is now deprecated, remove in the future.
    $self->{'Source-Version'} = $version;
}

=item $newstring = $s->substvars($string)

Substitutes variables in $string and return the result in $newstring.

=cut
sub substvars {
    my ($self, $v) = @_;
    my $lhs;
    my $vn;
    my $rhs = '';
    my $count = 0;

    while ($v =~ m/\$\{([-:0-9a-z]+)\}/i) {
        # If we have consumed more from the leftover data, then
        # reset the recursive counter.
        $count = 0 if (length($POSTMATCH) < length($rhs));

        $count < $maxsubsts ||
            error(_g("too many substitutions - recursive ? - in \`%s'"), $v);
        $lhs = $PREMATCH; $vn = $1; $rhs = $POSTMATCH;
        if (defined($self->{$vn})) {
            $v = $lhs . $self->{$vn} . $rhs;
            $count++;
        } else {
            warning(_g("unknown substitution variable \${%s}"), $vn);
            $v = $lhs . $rhs;
        }
    }
    return $v;
}

=back

=head1 AUTHOR

Raphael Hertzog <hertzog@debian.org>.

=cut

1;
