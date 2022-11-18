# Copyright © 2017, 2022 Guillem Jover <guillem@debian.org>
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

package Dpkg::OpenPGP::Backend;

use strict;
use warnings;

our $VERSION = '0.01';

use List::Util qw(first);

use Dpkg::Path qw(find_command);
use Dpkg::OpenPGP::ErrorCodes;

sub DEFAULT_CMDV {
    return [];
}

sub DEFAULT_CMDSTORE {
    return [];
}

sub DEFAULT_CMD {
    return [];
}

sub _detect_cmd {
    my ($cmd, $default) = @_;

    if (! defined $cmd || $cmd eq 'auto') {
        return first { find_command($_) } @{$default};
    } else {
        return find_command($cmd);
    }
}

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
        strict_verify => $opts{strict_verify} // 1,
    };
    bless $self, $class;

    $self->{cmdv} = _detect_cmd($opts{cmdv}, $self->DEFAULT_CMDV());
    $self->{cmdstore} = _detect_cmd($opts{cmdstore}, $self->DEFAULT_CMDSTORE());
    $self->{cmd} = _detect_cmd($opts{cmd}, $self->DEFAULT_CMD());

    return $self;
}

sub has_backend_cmd {
    my $self = shift;

    return defined $self->{cmd};
}

sub has_verify_cmd {
    my $self = shift;

    return defined $self->{cmd};
}

sub has_keystore {
    my $self = shift;

    return 0;
}

sub can_use_key {
    my ($self, $key) = @_;

    return $self->has_keystore() if $key->needs_keystore();
    return 1;
}

sub get_trusted_keyrings {
    my $self = shift;

    return ();
}

sub armor {
    my ($self, $type, $in, $out) = @_;

    return OPENPGP_UNSUPPORTED_SUBCMD;
}

sub dearmor {
    my ($self, $type, $in, $out) = @_;

    return OPENPGP_UNSUPPORTED_SUBCMD;
}

sub inline_verify {
    my ($self, $inlinesigned, $data, @certs) = @_;

    return OPENPGP_UNSUPPORTED_SUBCMD;
}

sub verify {
    my ($self, $data, $sig, @certs) = @_;

    return OPENPGP_UNSUPPORTED_SUBCMD;
}

sub inline_sign {
    my ($self, $data, $inlinesigned, $key) = @_;

    return OPENPGP_UNSUPPORTED_SUBCMD;
}

1;
