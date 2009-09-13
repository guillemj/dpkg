package Dpkg::Fields;

use strict;
use warnings;

use base qw(Exporter);
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Deps qw(@src_dep_fields @pkg_dep_fields);

our @EXPORT_OK = qw(capit unknown %control_src_fields %control_pkg_fields
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
    Priority Section Subarchitecture Tag Multi-Arch));
$control_pkg_fields{$_} = 1 foreach (@pkg_dep_fields);

our $control_src_field_regex = "(?:" . join("|", keys %control_src_fields) . ")";
our $control_pkg_field_regex = "(?:" . join("|", keys %control_pkg_fields) . ")";

# Some functions
sub capit {
    my @pieces = map { ucfirst(lc) } split /-/, $_[0];
    return join '-', @pieces;
}

sub unknown($$)
{
    my ($field, $desc) = @_;

    warning(_g("unknown information field '%s' in input data in %s"),
            $field, $desc);
}

1;
