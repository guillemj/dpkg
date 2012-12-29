# Copyright © 2007-2009 Raphaël Hertzog <hertzog@debian.org>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Control::Hash;

use strict;
use warnings;

our $VERSION = "1.00";

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

# This module must absolutely not use Dpkg::Control::Fields
# it's used by other modules that are required to compile
# Dpkg::Control::Fields itself (Dpkg::Vendor)
# That's why field_capitalize is duplicated

use base qw(Dpkg::Interface::Storable);

use overload
    '%{}' => sub { ${$_[0]}->{'fields'} },
    'eq' => sub { "$_[0]" eq "$_[1]" };

=encoding utf8

=head1 NAME

Dpkg::Control::Hash - parse and manipulate a block of RFC822-like fields

=head1 DESCRIPTION

The Dpkg::Control::Hash object is a hash-like representation of a set of
RFC822-like fields. The fields names are case insensitive and are always
capitalized the same when output (see field_capitalize function in
Dpkg::Control::Fields).
The order in which fields have been set is remembered and is used
to be able to dump back the same content. The output order can also be
overridden if needed.

You can store arbitrary values in the hash, they will always be properly
escaped in the output to conform to the syntax of control files. This is
relevant mainly for multilines values: while the first line is always output
unchanged directly after the field name, supplementary lines are
modified. Empty lines and lines containing only dots are prefixed with
" ." (space + dot) while other lines are prefixed with a single space.

During parsing, trailing spaces are stripped on all lines while leading
spaces are stripped only on the first line of each field.

=head1 FUNCTIONS

=over 4

=item my $c = Dpkg::Control::Hash->new(%opts)

Creates a new object with the indicated options. Supported options
are:

=over 8

=item allow_pgp

Configures the parser to accept PGP signatures around the control
information. Value can be 0 (default) or 1.

=item allow_duplicate

Configures the parser to allow duplicate fields in the control
information. Value can be 0 (default) or 1.

=item drop_empty

Defines if empty fields are dropped during the output. Value can be 0
(default) or 1.

=item name

The user friendly name of the information stored in the object. It might
be used in some error messages or warnings. A default name might be set
depending on the type.

=back

=cut

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    # Object is a scalar reference and not a hash ref to avoid
    # infinite recursion due to overloading hash-derefencing
    my $self = \{
        'in_order' => [],
        'out_order' => [],
        'allow_pgp' => 0,
        'allow_duplicate' => 0,
        'drop_empty' => 0,
    };
    bless $self, $class;

    $$self->{'fields'} = Dpkg::Control::Hash::Tie->new($self);

    # Options set by the user override default values
    $$self->{$_} = $opts{$_} foreach keys %opts;

    return $self;
}

# There is naturally a circular reference between the tied hash and its
# containing object. Happily, the extra layer of scalar reference can
# be used to detect the destruction of the object and break the loop so
# that everything gets garbage-collected.

sub DESTROY {
    my ($self) = @_;
    delete $$self->{'fields'};
}

=item $c->set_options($option, %opts)

Changes the value of one or more options.

=cut

sub set_options {
    my ($self, $k, $v) = @_;
    $$self->{$k} = $v;
}

=item my $value = $c->get_option($option)

Returns the value of the corresponding option.

=cut

sub get_option {
    my ($self, $k) = @_;
    return $$self->{$k};
}

=item $c->load($file)

Parse the content of $file. Exits in case of errors. Returns true if some
fields have been parsed.

=item $c->parse($fh, $description)

Parse a control file from the given filehandle. Exits in case of errors.
$description is used to describe the filehandle, ideally it's a filename
or a description of where the data comes from. It's used in error
messages. Returns true if some fields have been parsed.

=cut

sub parse {
    my ($self, $fh, $desc) = @_;

    my $paraborder = 1;
    my $parabody = 0;
    my $cf; # Current field
    my $expect_pgp_sig = 0;
    my $pgp_signed = 0;

    while (<$fh>) {
	s/\s*\n$//;
	next if (m/^$/ and $paraborder);
	next if (m/^#/);
	$paraborder = 0;
	if (m/^(\S+?)\s*:\s*(.*)$/) {
	    $parabody = 1;
	    if (exists $self->{$1}) {
		unless ($$self->{'allow_duplicate'}) {
		    syntaxerr($desc, sprintf(_g("duplicate field %s found"), $1));
		}
	    }
	    $self->{$1} = $2;
	    $cf = $1;
	} elsif (m/^\s(\s*\S.*)$/) {
	    my $line = $1;
	    unless (defined($cf)) {
                syntaxerr($desc, _g("continued value line not in field"));
            }
	    if ($line =~ /^\.+$/) {
		$line = substr $line, 1;
	    }
	    $self->{$cf} .= "\n$line";
	} elsif (m/^-----BEGIN PGP SIGNED MESSAGE-----$/) {
	    $expect_pgp_sig = 1;
	    if ($$self->{'allow_pgp'} and not $parabody) {
		# Skip PGP headers
		while (<$fh>) {
		    last if m/^\s*$/;
		}
	    } else {
		syntaxerr($desc, _g("PGP signature not allowed here"));
	    }
	} elsif (m/^$/ || ($expect_pgp_sig && m/^-----BEGIN PGP SIGNATURE-----$/)) {
	    if ($expect_pgp_sig) {
		# Skip empty lines
		$_ = <$fh> while defined($_) && $_ =~ /^\s*$/;
		length($_) ||
                    syntaxerr($desc, _g("expected PGP signature, found EOF " .
                                        "after blank line"));
		s/\s*\n$//;
		unless (m/^-----BEGIN PGP SIGNATURE-----$/) {
		    syntaxerr($desc, sprintf(_g("expected PGP signature, " .
                                                "found something else \`%s'"), $_));
                }
		# Skip PGP signature
		while (<$fh>) {
		    s/\s*\n$//;
		    last if m/^-----END PGP SIGNATURE-----$/;
		}
		unless (defined($_)) {
                    syntaxerr($desc, _g("unfinished PGP signature"));
                }
		# This does not mean the signature is correct, that needs to
		# be verified by gnupg.
		$pgp_signed = 1;
	    }
	    last; # Finished parsing one block
	} else {
	    syntaxerr($desc,
                      _g("line with unknown format (not field-colon-value)"));
	}
    }

    if ($expect_pgp_sig and not $pgp_signed) {
        syntaxerr($desc, _g("unfinished PGP signature"));
    }

    return defined($cf);
}

=item $c->find_custom_field($name)

Scan the fields and look for a user specific field whose name matches the
following regex: /X[SBC]*-$name/i. Return the name of the field found or
undef if nothing has been found.

=cut

sub find_custom_field {
    my ($self, $name) = @_;
    foreach my $key (keys %$self) {
        return $key if $key =~ /^X[SBC]*-\Q$name\E$/i;
    }
    return;
}

=item $c->get_custom_field($name)

Identify a user field and retrieve its value.

=cut

sub get_custom_field {
    my ($self, $name) = @_;
    my $key = $self->find_custom_field($name);
    return $self->{$key} if defined $key;
    return;
}

=item $c->save($filename)

Write the string representation of the control information to a
file.

=item my $str = $c->output()

=item "$c"

Get a string representation of the control information. The fields
are sorted in the order in which they have been read or set except
if the order has been overridden with set_output_order().

=item $c->output($fh)

Print the string representation of the control information to a
filehandle.

=cut

sub output {
    my ($self, $fh) = @_;
    my $str = "";
    my @keys;
    if (@{$$self->{'out_order'}}) {
        my $i = 1;
        my $imp = {};
        $imp->{$_} = $i++ foreach @{$$self->{'out_order'}};
        @keys = sort {
            if (defined $imp->{$a} && defined $imp->{$b}) {
                $imp->{$a} <=> $imp->{$b};
            } elsif (defined($imp->{$a})) {
                -1;
            } elsif (defined($imp->{$b})) {
                1;
            } else {
                $a cmp $b;
            }
        } keys %$self;
    } else {
        @keys = @{$$self->{'in_order'}};
    }

    foreach my $key (@keys) {
	if (exists $self->{$key}) {
	    my $value = $self->{$key};
            # Skip whitespace-only fields
            next if $$self->{'drop_empty'} and $value !~ m/\S/;
	    # Escape data to follow control file syntax
	    my @lines = split(/\n/, $value);
	    $value = (scalar @lines) ? shift @lines : "";
	    foreach (@lines) {
		s/\s+$//;
		if (/^$/ or /^\.+$/) {
		    $value .= "\n .$_";
		} else {
		    $value .= "\n $_";
		}
	    }
	    # Print it out
            if ($fh) {
	        print $fh "$key: $value\n" ||
                    syserr(_g("write error on control data"));
            }
	    $str .= "$key: $value\n" if defined wantarray;
	}
    }
    return $str;
}

=item $c->set_output_order(@fields)

Define the order in which fields will be displayed in the output() method.

=cut

sub set_output_order {
    my ($self, @fields) = @_;

    $$self->{'out_order'} = [@fields];
}

=item $c->apply_substvars($substvars)

Update all fields by replacing the variables references with
the corresponding value stored in the Dpkg::Substvars object.

=cut

sub apply_substvars {
    my ($self, $substvars, %opts) = @_;

    # Add substvars to refer to other fields
    foreach my $f (keys %$self) {
        $substvars->set_as_used("F:$f", $self->{$f});
    }

    foreach my $f (keys %$self) {
        my $v = $substvars->substvars($self->{$f}, %opts);
	if ($v ne $self->{$f}) {
	    # If we replaced stuff, ensure we're not breaking
	    # a dependency field by introducing empty lines, or multiple
	    # commas
	    $v =~ s/\n[ \t]*(\n|$)/$1/; # Drop empty/whitespace-only lines
	    # TODO: do this only for dependency fields
	    $v =~ s/,[\s,]*,/,/g;
	    $v =~ s/^\s*,\s*//;
	    $v =~ s/\s*,\s*$//;
	}
        $v =~ s/\$\{\}/\$/g; # XXX: what for?

        $self->{$f} = $v;
    }
}

package Dpkg::Control::Hash::Tie;

# This object is used to tie a hash. It implements hash-like functions by
# normalizing the name of fields received in keys (using
# Dpkg::Control::Fields::field_capitalize). It also stores the order in
# which fields have been added in order to be able to dump them in the
# same order. But the order information is stored in a parent object of
# type Dpkg::Control.

use Dpkg::ErrorHandling;
use Dpkg::Checksums;

use Tie::Hash;
use base qw(Tie::ExtraHash);

sub field_capitalize($) {
    my $field = lc(shift);
    # Some special cases due to history
    return "MD5sum" if $field eq "md5sum";
    return uc($field) if checksums_is_supported($field);
    # Generic case
    return join '-', map { ucfirst } split /-/, $field;
}

# $self->[0] is the real hash
# $self->[1] is a reference to the hash contained by the parent object.
# This reference bypasses the top-level scalar reference of a
# Dpkg::Control::Hash, hence ensuring that that reference gets DESTROYed
# properly.

# Dpkg::Control::Hash->new($parent)
#
# Return a reference to a tied hash implementing storage of simple
# "field: value" mapping as used in many Debian-specific files.

sub new {
    my $class = shift;
    my $hash = {};
    tie %{$hash}, $class, @_;
    return $hash;
}

sub TIEHASH  {
    my ($class, $parent) = @_;
    die "Parent object must be Dpkg::Control::Hash"
        if not $parent->isa("Dpkg::Control::Hash");
    return bless [ {}, $$parent ], $class;
}

sub FETCH {
    my ($self, $key) = @_;
    $key = lc($key);
    return $self->[0]->{$key} if exists $self->[0]->{$key};
    return;
}

sub STORE {
    my ($self, $key, $value) = @_;
    my $parent = $self->[1];
    $key = lc($key);
    if (not exists $self->[0]->{$key}) {
	push @{$parent->{'in_order'}}, field_capitalize($key);
    }
    $self->[0]->{$key} = $value;
}

sub EXISTS {
    my ($self, $key) = @_;
    $key = lc($key);
    return exists $self->[0]->{$key};
}

sub DELETE {
    my ($self, $key) = @_;
    my $parent = $self->[1];
    my $in_order = $parent->{'in_order'};
    $key = lc($key);
    if (exists $self->[0]->{$key}) {
	delete $self->[0]->{$key};
	@$in_order = grep { lc($_) ne $key } @$in_order;
	return 1;
    } else {
	return 0;
    }
}

sub FIRSTKEY {
    my $self = shift;
    my $parent = $self->[1];
    foreach (@{$parent->{'in_order'}}) {
	return $_ if exists $self->[0]->{lc($_)};
    }
}

sub NEXTKEY {
    my ($self, $last) = @_;
    my $parent = $self->[1];
    my $found = 0;
    foreach (@{$parent->{'in_order'}}) {
	if ($found) {
	    return $_ if exists $self->[0]->{lc($_)};
	} else {
	    $found = 1 if $_ eq $last;
	}
    }
    return;
}

1;

=back

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
