package Dpkg::Control::Types;

use base qw(Exporter);
our @EXPORT = qw(CTRL_UNKNOWN CTRL_INFO_SRC CTRL_INFO_PKG CTRL_INDEX_SRC
                 CTRL_INDEX_PKG CTRL_PKG_SRC CTRL_PKG_DEB CTRL_FILE_CHANGES
                 CTRL_FILE_VENDOR CTRL_FILE_STATUS CTRL_CHANGELOG);

=head1 NAME

Dpkg::Control::Types - export CTRL_* constants

=head1 DESCRIPTION

You should not use this module directly. Instead you more likely
want to use Dpkg::Control which also re-exports the same constants.

This module has been introduced solely to avoid a dependency loop
between Dpkg::Control and Dpkg::Control::Fields.

=cut

use constant {
    CTRL_UNKNOWN => 0,
    CTRL_INFO_SRC => 1,      # First control block in debian/control
    CTRL_INFO_PKG => 2,      # Subsequent control blocks in debian/control
    CTRL_INDEX_SRC => 4,     # Entry in APT's Packages files
    CTRL_INDEX_PKG => 8,     # Entry in APT's Sources files
    CTRL_PKG_SRC => 16,      # .dsc file of source package
    CTRL_PKG_DEB => 32,      # DEBIAN/control in binary packages
    CTRL_FILE_CHANGES => 64, # .changes file
    CTRL_FILE_VENDOR => 128, # File in /etc/dpkg/origins
    CTRL_FILE_STATUS => 256, # /var/lib/dpkg/status
    CTRL_CHANGELOG => 512,   # Output of dpkg-parsechangelog
};

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
