# Copyright © 2010-2011 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::BuildFlags;

use strict;
use warnings;

our $VERSION = "1.01";

use Dpkg::Gettext;
use Dpkg::BuildOptions;
use Dpkg::ErrorHandling;
use Dpkg::Vendor qw(run_vendor_hook);

=encoding utf8

=head1 NAME

Dpkg::BuildFlags - query build flags

=head1 DESCRIPTION

The Dpkg::BuildFlags object is used by dpkg-buildflags and can be used
to query the same information.

=head1 FUNCTIONS

=over 4

=item my $bf = Dpkg::BuildFlags->new()

Create a new Dpkg::BuildFlags object. It will be initialized based
on the value of several configuration files and environment variables.

=cut

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
    };
    bless $self, $class;
    $self->load_vendor_defaults();
    return $self;
}

=item $bf->load_vendor_defaults()

Reset the flags stored to the default set provided by the vendor.

=cut

sub load_vendor_defaults {
    my ($self) = @_;
    $self->{'options'} = {};
    $self->{'source'} = {};
    my $build_opts = Dpkg::BuildOptions->new();
    my $default_flags = $build_opts->has("noopt") ? "-g -O0" : "-g -O2";
    $self->{flags} = {
	CPPFLAGS => '',
	CFLAGS   => $default_flags,
	CXXFLAGS => $default_flags,
	FFLAGS   => $default_flags,
	LDFLAGS  => '',
    };
    $self->{origin} = {
	CPPFLAGS => 'vendor',
	CFLAGS   => 'vendor',
	CXXFLAGS => 'vendor',
	FFLAGS   => 'vendor',
	LDFLAGS  => 'vendor',
    };
    run_vendor_hook("update-buildflags", $self);
}

=item $bf->load_system_config()

Update flags from the system configuration.

=cut

sub load_system_config {
    my ($self) = @_;
    $self->update_from_conffile("/etc/dpkg/buildflags.conf", "system");
}

=item $bf->load_user_config()

Update flags from the user configuration.

=cut

sub load_user_config {
    my ($self) = @_;
    my $confdir = $ENV{'XDG_CONFIG_HOME'};
    $confdir ||= $ENV{'HOME'} . "/.config" if defined $ENV{'HOME'};
    if (defined $confdir) {
        $self->update_from_conffile("$confdir/dpkg/buildflags.conf", "user");
    }
}

=item $bf->load_environment_config()

Update flags based on user directives stored in the environment. See
dpkg-buildflags(1) for details.

=cut

sub load_environment_config {
    my ($self) = @_;
    foreach my $flag (keys %{$self->{flags}}) {
	my $envvar = "DEB_" . $flag . "_SET";
	if (exists $ENV{$envvar}) {
	    $self->set($flag, $ENV{$envvar}, "env");
	}
	$envvar = "DEB_" . $flag . "_APPEND";
	if (exists $ENV{$envvar}) {
	    $self->append($flag, $ENV{$envvar}, "env");
	}
	$envvar = "DEB_" . $flag . "_PREPEND";
	if (exists $ENV{$envvar}) {
	    $self->prepend($flag, $ENV{$envvar}, "env");
	}
    }
}

=item $bf->load_maintainer_config()

Update flags based on maintainer directives stored in the environment. See
dpkg-buildflags(1) for details.

=cut

sub load_maintainer_config {
    my ($self) = @_;
    foreach my $flag (keys %{$self->{flags}}) {
	my $envvar = "DEB_" . $flag . "_MAINT_SET";
	if (exists $ENV{$envvar}) {
	    $self->set($flag, $ENV{$envvar}, undef);
	}
	$envvar = "DEB_" . $flag . "_MAINT_APPEND";
	if (exists $ENV{$envvar}) {
	    $self->append($flag, $ENV{$envvar}, undef);
	}
	$envvar = "DEB_" . $flag . "_MAINT_PREPEND";
	if (exists $ENV{$envvar}) {
	    $self->prepend($flag, $ENV{$envvar}, undef);
	}
    }
}


=item $bf->load_config()

Call successively load_system_config(), load_user_config(),
load_environment_config() and load_maintainer_config() to update the
default build flags defined by the vendor.

=cut

sub load_config {
    my ($self) = @_;
    $self->load_system_config();
    $self->load_user_config();
    $self->load_environment_config();
    $self->load_maintainer_config();
}

=item $bf->set($flag, $value, $source)

Update the build flag $flag with value $value and record its origin as
$source (if defined).

=cut

sub set {
    my ($self, $flag, $value, $src) = @_;
    $self->{flags}->{$flag} = $value;
    $self->{origin}->{$flag} = $src if defined $src;
}

=item $bf->append($flag, $value, $source)

Append the options listed in $value to the current value of the flag $flag.
Record its origin as $source (if defined).

=cut

sub append {
    my ($self, $flag, $value, $src) = @_;
    if (length($self->{flags}->{$flag})) {
        $self->{flags}->{$flag} .= " $value";
    } else {
        $self->{flags}->{$flag} = $value;
    }
    $self->{origin}->{$flag} = $src if defined $src;
}

=item $bf->prepend($flag, $value, $source)

Prepend the options listed in $value to the current value of the flag $flag.
Record its origin as $source (if defined).

=cut

sub prepend {
    my ($self, $flag, $value, $src) = @_;
    if (length($self->{flags}->{$flag})) {
        $self->{flags}->{$flag} = "$value " . $self->{flags}->{$flag};
    } else {
        $self->{flags}->{$flag} = $value;
    }
    $self->{origin}->{$flag} = $src if defined $src;
}


=item $bf->update_from_conffile($file, $source)

Update the current build flags based on the configuration directives
contained in $file. See dpkg-buildflags(1) for the format of the directives.

$source is the origin recorded for any build flag set or modified.

=cut

sub update_from_conffile {
    my ($self, $file, $src) = @_;
    return unless -e $file;
    open(CNF, "<", $file) or syserr(_g("cannot read %s"), $file);
    while(<CNF>) {
        chomp;
        next if /^\s*#/; # Skip comments
        next if /^\s*$/; # Skip empty lines
        if (/^(append|prepend|set)\s+(\S+)\s+(\S.*\S)\s*$/i) {
            my ($op, $flag, $value) = ($1, $2, $3);
            unless (exists $self->{flags}->{$flag}) {
                warning(_g("line %d of %s mentions unknown flag %s"), $., $file, $flag);
                $self->{flags}->{$flag} = "";
            }
            if (lc($op) eq "set") {
                $self->set($flag, $value, $src);
            } elsif (lc($op) eq "append") {
                $self->append($flag, $value, $src);
            } elsif (lc($op) eq "prepend") {
                $self->prepend($flag, $value, $src);
            }
        } else {
            warning(_g("line %d of %s is invalid, it has been ignored."), $., $file);
        }
    }
    close(CNF);
}

=item $bf->get($flag)

Return the value associated to the flag. It might be undef if the
flag doesn't exist.

=cut

sub get {
    my ($self, $key) = @_;
    return $self->{'flags'}{$key};
}

=item $bf->get_origin($flag)

Return the origin associated to the flag. It might be undef if the
flag doesn't exist.

=cut

sub get_origin {
    my ($self, $key) = @_;
    return $self->{'origin'}{$key};
}

=item $bf->has($option)

Returns a boolean indicating whether the flags exists in the object.

=cut

sub has {
    my ($self, $key) = @_;
    return exists $self->{'flags'}{$key};
}

=item my @flags = $bf->list()

Returns the list of flags stored in the object.

=cut

sub list {
    my ($self) = @_;
    return sort keys %{$self->{'flags'}};
}

=back

=head1 CHANGES

=head2 Version 1.01

New method: $bf->prepend() very similar to append(). Implement support of
the prepend operation everywhere.

New method: $bf->load_maintainer_config() that update the build flags
based on the package maintainer directives.

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>

=cut

1;
