# Copyright © 2009-2010 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::Conf;

use strict;
use warnings;

our $VERSION = '1.02';

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

use parent qw(Dpkg::Interface::Storable);

use overload
    '@{}' => sub { return [ $_[0]->get_options() ] },
    fallback => 1;

=encoding utf8

=head1 NAME

Dpkg::Conf - parse dpkg configuration files

=head1 DESCRIPTION

The Dpkg::Conf object can be used to read options from a configuration
file. It can export an array that can then be parsed exactly like @ARGV.

=head1 METHODS

=over 4

=item $conf = Dpkg::Conf->new(%opts)

Create a new Dpkg::Conf object. Some options can be set through %opts:
if allow_short evaluates to true (it defaults to false), then short
options are allowed in the configuration file, they should be prepended
with a single hyphen.

=cut

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
	options => {},
	allow_short => 0,
    };
    foreach my $opt (keys %opts) {
	$self->{$opt} = $opts{$opt};
    }
    bless $self, $class;

    return $self;
}

=item @$conf

=item @options = $conf->get_options()

Returns the list of options that can be parsed like @ARGV.

=cut

sub get_options {
    my $self = shift;
    my @options;

    foreach my $name (sort keys %{$self->{options}}) {
        my $value = $self->{options}->{$name};

        $name = "--$name" unless $name =~ /^-/;
        if (defined $value) {
            push @options, "$name=$value";
        } else {
            push @options, $name;
        }
    }

    return @options;
}

=item $value = $conf->get($name)

Returns the value of option $name, where the option name should not have "--"
prefixed. If the option is not present the function will return undef.

=cut

sub get {
    my ($self, $name) = @_;

    return $self->{options}->{$name};
}

=item $conf->set($name, $value)

Set the $value of option $name, where the option name should not have "--"
prefixed.

=cut

sub set {
    my ($self, $name, $value) = @_;

    $self->{options}->{$name} = $value;
}

=item $conf->load($file)

Read options from a file. Return the number of options parsed.

=item $conf->parse($fh)

Parse options from a file handle. Return the number of options parsed.

=cut

sub parse {
    my ($self, $fh, $desc) = @_;
    my $count = 0;
    local $_;

    while (<$fh>) {
	chomp;
	s/^\s+//;             # Strip leading spaces
	s/\s+$//;             # Strip trailing spaces
	s/\s+=\s+/=/;         # Remove spaces around the first =
	s/\s+/=/ unless m/=/; # First spaces becomes = if no =
	# Skip empty lines and comments
	next if /^#/ or length == 0;
	if (/^-[^-]/ and not $self->{allow_short}) {
	    warning(g_('short option not allowed in %s, line %d'), $desc, $.);
	    next;
	}
	if (/^([^=]+)(?:=(.*))?$/) {
	    my ($name, $value) = ($1, $2);
	    if (defined $value) {
		$value =~ s/^"(.*)"$/$1/ or $value =~ s/^'(.*)'$/$1/;
	    }
	    $name =~ s/^--//;
	    $self->{options}->{$name} = $value;
	    $count++;
	} else {
	    warning(g_('invalid syntax for option in %s, line %d'), $desc, $.);
	}
    }
    return $count;
}

=item $conf->filter(%opts)

Filter the list of options, either removing or keeping all those that
return true when &$opts{remove}($option) or &opts{keep}($option) is called.
If $opts{format_argv} is true the long options passed to the filter
functions will have "--" prefixed.

=cut

sub filter {
    my ($self, %opts) = @_;
    my $remove = $opts{remove} // sub { 0 };
    my $keep = $opts{keep} // sub { 1 };

    foreach my $name (keys %{$self->{options}}) {
        my $option = $name;

        if ($opts{format_argv}) {
            $option = "--$name" unless $name =~ /^-/;
        }
        if (&$remove($option) or not &$keep($option)) {
            delete $self->{options}->{$name};
        }
    }
}

=item $string = $conf->output($fh)

Write the options in the given filehandle (if defined) and return a string
representation of the content (that would be) written.

=item "$conf"

Return a string representation of the content.

=item $conf->save($file)

Save the options in a file.

=cut

sub output {
    my ($self, $fh) = @_;
    my $ret = '';

    foreach my $name (sort keys %{$self->{options}}) {
	my $value = $self->{options}->{$name};

	my $opt = $name;
	$opt .= " = \"$value\"" if defined $value;
	$opt .= "\n";
	print { $fh } $opt if defined $fh;
	$ret .= $opt;
    }
    return $ret;
}

=back

=head1 CHANGES

=head2 Version 1.02 (dpkg 1.18.5)

New option: Accept new option 'format_argv' in $conf->filter().

New methods: $conf->get(), $conf->set().

=head2 Version 1.01 (dpkg 1.15.8)

New method: $conf->filter()

=head2 Version 1.00 (dpkg 1.15.6)

Mark the module as public.

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
