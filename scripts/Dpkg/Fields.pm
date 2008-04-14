package Dpkg::Fields;

use strict;
use warnings;

use Exporter;
use Dpkg::Deps qw(@src_dep_fields @pkg_dep_fields);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(capit %control_src_fields %control_pkg_fields
    $control_src_field_regex $control_pkg_field_regex);
our %EXPORT_TAGS = ('list' => [qw(%control_src_fields %control_pkg_fields
			$control_src_field_regex $control_pkg_field_regex)]);

# Some variables (list of fields)
our %control_src_fields;
our %control_pkg_fields;
$control_src_fields{$_} = 1 foreach (qw(Bugs Dm-Upload-Allowed
    Homepage Origin Maintainer Priority Section Source Standards-Version
    Uploaders Vcs-Browser Vcs-Arch Vcs-Bzr Vcs-Cvs Vcs-Darcs Vcs-Git Vcs-Hg
    Vcs-Mtn Vcs-Svn));
$control_src_fields{$_} = 1 foreach (@src_dep_fields);
$control_pkg_fields{$_} = 1 foreach (qw(Architecture Bugs Description Essential
    Homepage Installer-Menu-Item Kernel-Version Package Package-Type
    Priority Section Subarchitecture Tag));
$control_pkg_fields{$_} = 1 foreach (@pkg_dep_fields);

our $control_src_field_regex = "(?:" . join("|", keys %control_src_fields) . ")";
our $control_pkg_field_regex = "(?:" . join("|", keys %control_pkg_fields) . ")";

# Some functions
sub capit {
    my @pieces = map { ucfirst(lc) } split /-/, $_[0];
    return join '-', @pieces;
}

package Dpkg::Fields::Object;

=head1 OTHER OBJECTS

=head2 Dpkg::Fields::Object

This object is used to tie a hash. It implements hash-like functions by
normalizing the name of fields received in keys (using
Dpkg::Fields::capit). It also stores the order in which fields have been
added in order to be able to dump them in the same order.

=cut
use Tie::Hash;
our @ISA = qw(Tie::ExtraHash Tie::Hash);

use Dpkg::ErrorHandling qw(internerr syserr);
use Dpkg::Gettext;

# Import capit
Dpkg::Fields->import('capit');

# $self->[0] is the real hash
# $self->[1] is an array containing the ordered list of keys
# $self->[2] is an hash describing the relative importance of each field
# (used to sort the output).

=head2 Dpkg::Fields::Object->new()

Return a reference to a tied hash implementing storage of simple
"field: value" mapping as used in many Debian-specific files.

=cut
sub new {
    my $hash = {};
    tie %{$hash}, 'Dpkg::Fields::Object';
    return $hash;
}

sub TIEHASH  {
    my $class = shift;
    return bless [{}, [], {}], $class;
}

sub FETCH {
    my ($self, $key) = @_;
    $key = capit($key);
    return $self->[0]->{$key} if exists $self->[0]->{$key};
    return undef;
}

sub STORE {
    my ($self, $key, $value) = @_;
    $key = capit($key);
    if (not exists $self->[0]->{$key}) {
	push @{$self->[1]}, $key;
    }
    $self->[0]->{$key} = $value;
}

sub EXISTS {
    my ($self, $key) = @_;
    $key = capit($key);
    return exists $self->[0]->{$key};
}

sub DELETE {
    my ($self, $key) = @_;
    $key = capit($key);
    if (exists $self->[0]->{$key}) {
	delete $self->[0]->{$key};
	@{$self->[1]} = grep { $_ ne $key } @{$self->[1]};
	return 1;
    } else {
	return 0;
    }
}

sub FIRSTKEY {
    my $self = shift;
    foreach (@{$self->[1]}) {
	return $_ if exists $self->[0]->{$_};
    }
}

sub NEXTKEY {
    my ($self, $last) = @_;
    my $found = 0;
    foreach (@{$self->[1]}) {
	if ($found) {
	    return $_ if exists $self->[0]->{$_};
	} else {
	    $found = 1 if $_ eq $last;
	}
    }
    return undef;
}

=head2 tied(%hash)->find_custom_field($name)

Scan the fields and look for a user specific field whose name matches the
following regex: /X[SBC]+-$name/i. Return the name of the field found or
undef if nothing has been found.

=cut
sub find_custom_field {
    my ($self, $name) = @_;
    foreach my $key (keys %{$self->[0]}) {
        return $key if $key =~ /^X[SBC]*-\Q$name\E$/i;
    }
    return undef;
}

=head2 tied(%hash)->get_custom_field($name)

Identify a user field and retrieve its value.

=cut
sub get_custom_field {
    my ($self, $name) = @_;
    my $key = $self->find_custom_field($name);
    return $self->[0]->{$key} if defined $key;
    return undef;
}

=head2 my $str = tied(%hash)->dump()
=head2 tied(%hash)->dump($fh)

Dump the raw content of the hash either as a string or to a filehandle.

=cut
sub dump {
    my ($self, $fh) = @_;
    my $str = "";
    foreach (@{$self->[1]}) {
	if (exists $self->[0]->{$_}) {
	    print $fh "$_: " . $self->[0]->{$_} . "\n" if $fh;
	    $str .= "$_: " . $self->[0]->{$_} . "\n" if defined wantarray;
	}
    }
    return $str;
}

=head2 tied(%hash)->set_field_importance(@fields)

Define the order in which fields will be displayed in the output() method.

=cut
sub set_field_importance {
    my ($self, @fields) = @_;
    my $i = 1;

    $self->[2] = {};
    $self->[2]{$_} = $i++ foreach (@fields);
}

=head2 tied(%hash)->output($fh, $substvars)

If $fh is defined, print the fields on the $fh filehandle after
substitution of variables defined in the Dpkg::Substvars object.

Also returns the string of what would printed on the filehandle.

=cut
sub output {
    my ($self, $fh, $substvars) = @_;
    my $str = "";
    my $imp = $self->[2]; # Hash of relative importance

    # Add substvars to refer to other fields
    if (defined($substvars)) {
	foreach my $f (keys %{$self->[0]}) {
	    $substvars->set("F:$f", $self->[0]->{$f});
	}
    }

    my @keys = sort {
	if (defined $imp->{$a} && defined $imp->{$b}) {
	    $imp->{$a} <=> $imp->{$b};
	} elsif (defined($imp->{$a})) {
	    -1;
	} elsif (defined($imp->{$b})) {
	    1;
	} else {
	    $a cmp $b;
	}
    } keys %{$self->[0]};

    foreach my $f (@keys) {
        my $v = $self->[0]->{$f};
        if (defined($substvars)) {
            $v = $substvars->substvars($v);
        }
        $v =~ m/\S/ || next; # delete whitespace-only fields
        $v =~ m/\n\S/ &&
            internerr(_g("field %s has newline then non whitespace >%s<"),
                      $f, $v);
        $v =~ m/\n[ \t]*\n/ &&
            internerr(_g("field %s has blank lines >%s<"), $f, $v);
        $v =~ m/\n$/ &&
            internerr(_g("field %s has trailing newline >%s<"), $f, $v);
        if (defined($substvars)) {
           $v =~ s/,[\s,]*,/,/g;
           $v =~ s/^\s*,\s*//;
           $v =~ s/\s*,\s*$//;
        }
        $v =~ s/\$\{\}/\$/g;
	if ($fh) {
	    print $fh "$f: $v\n" || syserr(_g("write error on control data"));
	}
	if (defined wantarray) {
	    $str .= "$f: $v\n";
	}
    }
    return $str;
}

1;
