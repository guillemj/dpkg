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
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Vendor::Debian;

use strict;
use warnings;

our $VERSION = "0.01";

use base qw(Dpkg::Vendor::Default);
use Dpkg::Control::Types;
use Dpkg::Vendor::Ubuntu;

=encoding utf8

=head1 NAME

Dpkg::Vendor::Debian - Debian vendor object

=head1 DESCRIPTION

This vendor object customize the behaviour of dpkg scripts
for Debian specific actions.

=cut

sub run_hook {
    my ($self, $hook, @params) = @_;

    if ($hook eq "keyrings") {
        return ('/usr/share/keyrings/debian-keyring.gpg',
                '/usr/share/keyrings/debian-maintainers.gpg');
    } elsif ($hook eq "register-custom-fields") {
        return (
            [ "register", "Dm-Upload-Allowed",
              CTRL_INFO_SRC | CTRL_INDEX_SRC | CTRL_PKG_SRC ],
            [ "insert_after", CTRL_INDEX_SRC, "Uploaders", "Dm-Upload-Allowed" ],
            [ "insert_after", CTRL_PKG_SRC, "Uploaders", "Dm-Upload-Allowed" ],
        );
    } elsif ($hook eq "extend-patch-header") {
        my ($textref, $ch_info) = @params;
	if ($ch_info->{'Closes'}) {
	    foreach my $bug (split(/\s+/, $ch_info->{'Closes'})) {
		$$textref .= "Bug-Debian: http://bugs.debian.org/$bug\n";
	    }
	}

	my $b = Dpkg::Vendor::Ubuntu::find_launchpad_closes($ch_info->{'Changes'});
	foreach my $bug (@$b) {
	    $$textref .= "Bug-Ubuntu: https://bugs.launchpad.net/bugs/$bug\n";
	}
    } else {
        return $self->SUPER::run_hook($hook, @params);
    }
}

1;
