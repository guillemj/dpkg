# Copyright © 2007,2009 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Substvars;

use strict;
use warnings;

use Dpkg qw($version);
use Dpkg::Arch qw(get_host_arch);
use Dpkg::ErrorHandling;
use Dpkg::Gettext;

use POSIX qw(:errno_h);

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
generic substitutions like ${Newline}, ${Space}, ${Tab}, ${dpkg:Version}
and ${dpkg:Upstream-Version}.

Additional substitutions will be read from the $file passed as parameter.

It keeps track of which substitutions were actually used (only counting
substvars(), not get()), and warns about unused substvars when asked to. The
substitutions that are always present are not included in these warnings.

=cut

sub new {
    my ($this, $arg) = @_;
    my $class = ref($this) || $this;
    my $self = {
        vars => {
            "Newline" => "\n",
            "Space" => " ",
            "Tab" => "\t",
            "dpkg:Version" => $version,
            "dpkg:Upstream-Version" => $version,
            },
        used => {},
    };
    $self->{'vars'}{'dpkg:Upstream-Version'} =~ s/-[^-]+$//;
    bless $self, $class;
    $self->no_warn($_) foreach keys %{$self->{'vars'}};
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
    $self->{'vars'}{$key} = $value;
}

=item $s->get($key)

Get the value of a given substitution.

=cut

sub get {
    my ($self, $key) = @_;
    return $self->{'vars'}{$key};
}

=item $s->delete($key)

Remove a given substitution.

=cut

sub delete {
    my ($self, $key) = @_;
    delete $self->{'used'}{$key};
    return delete $self->{'vars'}{$key};
}

=item $s->no_warn($key)

Prevents warnings about a unused substitution, for example if it is provided by
default.

=cut

sub no_warn {
    my ($self, $key) = @_;
    $self->{'used'}{$key}++;
}

=item $s->parse($file)

Add new substitutions read from $file.

=cut

sub parse {
    my ($self, $varlistfile) = @_;
    $varlistfile = "./$varlistfile" if $varlistfile =~ m/\s/;
    if (open(SV, "<", $varlistfile)) {
	binmode(SV);
	while (<SV>) {
	    next if m/^\s*\#/ || !m/\S/;
	    s/\s*\n$//;
	    m/^(\w[-:0-9A-Za-z]*)\=(.*)$/ ||
		error(_g("bad line in substvars file %s at line %d"),
		      $varlistfile, $.);
	    $self->{'vars'}{$1} = $2;
	}
	close(SV);
    } elsif ($! != ENOENT) {
	error(_g("unable to open substvars file %s: %s"), $varlistfile, $!);
    }
}

=item $s->set_version_substvars($version)

Defines ${binary:Version}, ${source:Version} and
${source:Upstream-Version} based on the given version string.

These will never be warned about when unused.

=cut

sub set_version_substvars {
    my ($self, $version) = @_;

    $self->{'vars'}{'binary:Version'} = $version;
    $self->{'vars'}{'source:Version'} = $version;
    $self->{'vars'}{'source:Version'} =~ s/\+b[0-9]+$//;
    $self->{'vars'}{'source:Upstream-Version'} = $version;
    $self->{'vars'}{'source:Upstream-Version'} =~ s/-[^-]*$//;

    # XXX: Source-Version is now deprecated, remove in the future.
    $self->{'vars'}{'Source-Version'} = $version;

    $self->no_warn($_) foreach qw/binary:Version source:Version source:Upstream-Version Source-Version/;
}

=item $s->set_arch_substvars()

Defines architecture variables: ${Arch}.

This will never be warned about when unused.

=cut

sub set_arch_substvars {
    my ($self) = @_;

    $self->{'vars'}{'Arch'} = get_host_arch();
    $self->no_warn('Arch');
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

    while ($v =~ m/^(.*?)\$\{([-:0-9a-z]+)\}(.*)$/si) {
        # If we have consumed more from the leftover data, then
        # reset the recursive counter.
        $count = 0 if (length($3) < length($rhs));

        $count < $maxsubsts ||
            error(_g("too many substitutions - recursive ? - in \`%s'"), $v);
        $lhs = $1; $vn = $2; $rhs = $3;
        if (defined($self->{'vars'}{$vn})) {
            $v = $lhs . $self->{'vars'}{$vn} . $rhs;
	    $self->no_warn($vn);
            $count++;
        } else {
            warning(_g("unknown substitution variable \${%s}"), $vn);
            $v = $lhs . $rhs;
        }
    }
    return $v;
}

=item $s->warn_about_unused()

Issues warning about any variables that were set, but not used

=cut

sub warn_about_unused {
    my ($self) = @_;

    foreach my $vn (keys %{$self->{'vars'}}) {
        next if $self->{'used'}{$vn};
        # Empty substitutions variables are ignored on the basis
        # that they are not required in the current situation
        # (example: debhelper's misc:Depends in many cases)
        next if $self->{'vars'}{$vn} eq "";
        warning(_g("unused substitution variable \${%s}"), $vn);
    }
}

=back

=head1 AUTHOR

Raphael Hertzog <hertzog@debian.org>.

=cut

1;
