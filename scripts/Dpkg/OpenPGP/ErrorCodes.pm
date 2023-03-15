# Copyright © 2022 Guillem Jover <guillem@debian.org>
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

Dpkg::OpenPGP::ErrorCodes - OpenPGP error codes

=head1 DESCRIPTION

This module provides error codes handling to be used by the various
OpenPGP backends.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::OpenPGP::ErrorCodes 0.01;

use strict;
use warnings;

our @EXPORT = qw(
    OPENPGP_OK
    OPENPGP_NO_SIG
    OPENPGP_MISSING_ARG
    OPENPGP_UNSUPPORTED_OPTION
    OPENPGP_BAD_DATA
    OPENPGP_EXPECTED_TEXT
    OPENPGP_OUTPUT_EXISTS
    OPENPGP_MISSING_INPUT
    OPENPGP_KEY_IS_PROTECTED
    OPENPGP_UNSUPPORTED_SUBCMD
    OPENPGP_KEY_CANNOT_SIGN

    OPENPGP_MISSING_CMD
    OPENPGP_NEEDS_KEYSTORE
    OPENPGP_CMD_CANNOT_SIGN

    openpgp_errorcode_to_string
);

use Exporter qw(import);

use Dpkg::Gettext;

# Error codes based on
# https://ietf.org/archive/id/draft-dkg-openpgp-stateless-cli-04.html#section-6
#
# Local error codes use a negative number, as that should not conflict with
# the SOP exit codes.

use constant {
    OPENPGP_OK => 0,
    OPENPGP_NO_SIG => 3,
    OPENPGP_MISSING_ARG => 19,
    OPENPGP_UNSUPPORTED_OPTION => 37,
    OPENPGP_BAD_DATA => 41,
    OPENPGP_EXPECTED_TEXT => 53,
    OPENPGP_OUTPUT_EXISTS => 59,
    OPENPGP_MISSING_INPUT => 61,
    OPENPGP_KEY_IS_PROTECTED => 67,
    OPENPGP_UNSUPPORTED_SUBCMD => 69,
    OPENPGP_KEY_CANNOT_SIGN => 79,

    OPENPGP_MISSING_CMD => -1,
    OPENPGP_NEEDS_KEYSTORE => -2,
    OPENPGP_CMD_CANNOT_SIGN => -3,
};

my %code2error = (
    OPENPGP_OK() => N_('success'),
    OPENPGP_NO_SIG() => N_('no acceptable signature found'),
    OPENPGP_MISSING_ARG() => N_('missing required argument'),
    OPENPGP_UNSUPPORTED_OPTION() => N_('unsupported option'),
    OPENPGP_BAD_DATA() => N_('invalid data type'),
    OPENPGP_EXPECTED_TEXT() => N_('non-text input where text expected'),
    OPENPGP_OUTPUT_EXISTS() => N_('output file already exists'),
    OPENPGP_MISSING_INPUT() => N_('input file does not exist'),
    OPENPGP_KEY_IS_PROTECTED() => N_('cannot unlock password-protected key'),
    OPENPGP_UNSUPPORTED_SUBCMD() => N_('unsupported subcommand'),
    OPENPGP_KEY_CANNOT_SIGN() => N_('key is not signature-capable'),

    OPENPGP_MISSING_CMD() => N_('missing OpenPGP implementation'),
    OPENPGP_NEEDS_KEYSTORE() => N_('specified key needs a keystore'),
    OPENPGP_CMD_CANNOT_SIGN() => N_('OpenPGP backend command cannot sign'),
);

sub openpgp_errorcode_to_string
{
    my $code = shift;

    return gettext($code2error{$code}) if exists $code2error{$code};
    return sprintf g_('error code %d'), $code;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
