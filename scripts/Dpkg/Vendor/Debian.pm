# Copyright © 2009-2011 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2009, 2011-2015 Guillem Jover <guillem@debian.org>
#
# Hardening build flags handling derived from work of:
# Copyright © 2009-2011 Kees Cook <kees@debian.org>
# Copyright © 2007-2008 Canonical, Ltd.
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

package Dpkg::Vendor::Debian;

use strict;
use warnings;

our $VERSION = '0.01';

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control::Types;
use Dpkg::BuildOptions;
use Dpkg::Arch qw(get_host_arch debarch_to_debtriplet);

use parent qw(Dpkg::Vendor::Default);

=encoding utf8

=head1 NAME

Dpkg::Vendor::Debian - Debian vendor object

=head1 DESCRIPTION

This vendor object customize the behaviour of dpkg scripts
for Debian specific actions.

=cut

sub run_hook {
    my ($self, $hook, @params) = @_;

    if ($hook eq 'keyrings') {
        return ('/usr/share/keyrings/debian-keyring.gpg',
                '/usr/share/keyrings/debian-maintainers.gpg');
    } elsif ($hook eq 'builtin-build-depends') {
        return qw(build-essential:native);
    } elsif ($hook eq 'builtin-build-conflicts') {
        return ();
    } elsif ($hook eq 'register-custom-fields') {
    } elsif ($hook eq 'extend-patch-header') {
        my ($textref, $ch_info) = @params;
	if ($ch_info->{'Closes'}) {
	    foreach my $bug (split(/\s+/, $ch_info->{'Closes'})) {
		$$textref .= "Bug-Debian: https://bugs.debian.org/$bug\n";
	    }
	}

	# XXX: Layer violation...
	require Dpkg::Vendor::Ubuntu;
	my $b = Dpkg::Vendor::Ubuntu::find_launchpad_closes($ch_info->{'Changes'});
	foreach my $bug (@$b) {
	    $$textref .= "Bug-Ubuntu: https://bugs.launchpad.net/bugs/$bug\n";
	}
    } elsif ($hook eq 'update-buildflags') {
	$self->_add_qa_flags(@params);
	$self->_add_reproducible_flags(@params);
	$self->_add_sanitize_flags(@params);
	$self->_add_hardening_flags(@params);
    } else {
        return $self->SUPER::run_hook($hook, @params);
    }
}

sub _parse_build_options {
    my ($self, $variable, $area, $use_feature) = @_;

    # Adjust features based on user or maintainer's desires.
    my $opts = Dpkg::BuildOptions->new(envvar => $variable);
    foreach my $feature (split(/,/, $opts->get($area) // '')) {
	$feature = lc($feature);
	if ($feature =~ s/^([+-])//) {
	    my $value = ($1 eq '+') ? 1 : 0;
	    if ($feature eq 'all') {
		$use_feature->{$_} = $value foreach keys %{$use_feature};
	    } else {
		if (exists $use_feature->{$feature}) {
		    $use_feature->{$feature} = $value;
		} else {
		    warning(g_('unknown %s feature in %s variable: %s'),
		            $area, $variable, $feature);
		}
	    }
	} else {
	    warning(g_('incorrect value in %s option of %s variable: %s'),
	            $area, $variable, $feature);
	}
    }
}

sub _parse_feature_area {
    my ($self, $area, $use_feature) = @_;

    $self->_parse_build_options('DEB_BUILD_OPTIONS', $area, $use_feature);
    $self->_parse_build_options('DEB_BUILD_MAINT_OPTIONS', $area, $use_feature);
}

sub _add_qa_flags {
    my ($self, $flags) = @_;

    # Default feature states.
    my %use_feature = (
        bug => 0,
        canary => 0,
    );

    # Adjust features based on user or maintainer's desires.
    $self->_parse_feature_area('qa', \%use_feature);

    # Warnings that detect actual bugs.
    if ($use_feature{bug}) {
        foreach my $warnflag (qw(array-bounds clobbered volatile-register-var
                                 implicit-function-declaration)) {
            $flags->append('CFLAGS', "-Werror=$warnflag");
            $flags->append('CXXFLAGS', "-Werror=$warnflag");
        }
    }

    # Inject dummy canary options to detect issues with build flag propagation.
    if ($use_feature{canary}) {
        require Digest::MD5;
        my $id = Digest::MD5::md5_hex(int rand 4096);

        foreach my $flag (qw(CPPFLAGS CFLAGS OBJCFLAGS CXXFLAGS OBJCXXFLAGS)) {
            $flags->append($flag, "-D__DEB_CANARY_${flag}_${id}__");
        }
        $flags->append('LDFLAGS', "-Wl,-z,deb-canary-${id}");
    }

    # Store the feature usage.
    while (my ($feature, $enabled) = each %use_feature) {
        $flags->set_feature('qa', $feature, $enabled);
    }
}

sub _add_reproducible_flags {
    my ($self, $flags) = @_;

    # Default feature states.
    my %use_feature = (
        timeless => 1,
    );

    # Adjust features based on user or maintainer's desires.
    $self->_parse_feature_area('reproducible', \%use_feature);

    # Warn when the __TIME__, __DATE__ and __TIMESTAMP__ macros are used.
    if ($use_feature{timeless}) {
       $flags->append('CPPFLAGS', '-Wdate-time');
    }

    # Store the feature usage.
    while (my ($feature, $enabled) = each %use_feature) {
       $flags->set_feature('reproducible', $feature, $enabled);
    }
}

sub _add_sanitize_flags {
    my ($self, $flags) = @_;

    # Default feature states.
    my %use_feature = (
        address => 0,
        thread => 0,
        leak => 0,
        undefined => 0,
    );

    # Adjust features based on user or maintainer's desires.
    $self->_parse_feature_area('sanitize', \%use_feature);

    # Handle logical feature interactions.
    if ($use_feature{address} and $use_feature{thread}) {
        # Disable the thread sanitizer when the address one is active, they
        # are mutually incompatible.
        $use_feature{thread} = 0;
    }
    if ($use_feature{address} or $use_feature{thread}) {
        # Disable leak sanitizer, it is implied by the address or thread ones.
        $use_feature{leak} = 0;
    }

    if ($use_feature{address}) {
        my $flag = '-fsanitize=address -fno-omit-frame-pointer';
        $flags->append('CFLAGS', $flag);
        $flags->append('CXXFLAGS', $flag);
        $flags->append('LDFLAGS', '-fsanitize=address');
    }

    if ($use_feature{thread}) {
        my $flag = '-fsanitize=thread';
        $flags->append('CFLAGS', $flag);
        $flags->append('CXXFLAGS', $flag);
        $flags->append('LDFLAGS', $flag);
    }

    if ($use_feature{leak}) {
        $flags->append('LDFLAGS', '-fsanitize=leak');
    }

    if ($use_feature{undefined}) {
        my $flag = '-fsanitize=undefined';
        $flags->append('CFLAGS', $flag);
        $flags->append('CXXFLAGS', $flag);
        $flags->append('LDFLAGS', $flag);
    }

    # Store the feature usage.
    while (my ($feature, $enabled) = each %use_feature) {
       $flags->set_feature('sanitize', $feature, $enabled);
    }
}

sub _add_hardening_flags {
    my ($self, $flags) = @_;
    my $arch = get_host_arch();
    my ($abi, $os, $cpu) = debarch_to_debtriplet($arch);

    unless (defined $abi and defined $os and defined $cpu) {
        warning(g_("unknown host architecture '%s'"), $arch);
        ($abi, $os, $cpu) = ('', '', '');
    }

    # Default feature states.
    my %use_feature = (
	pie => 0,
	stackprotector => 1,
	stackprotectorstrong => 1,
	fortify => 1,
	format => 1,
	relro => 1,
	bindnow => 0,
    );

    # Adjust features based on user or maintainer's desires.
    $self->_parse_feature_area('hardening', \%use_feature);

    # Mask features that are not available on certain architectures.
    if ($os !~ /^(?:linux|knetbsd|hurd)$/ or
	$cpu =~ /^(?:hppa|avr32)$/) {
	# Disabled on non-linux/knetbsd/hurd (see #430455 and #586215).
	# Disabled on hppa, avr32
	#  (#574716).
	$use_feature{pie} = 0;
    }
    if ($cpu =~ /^(?:ia64|alpha|hppa)$/ or $arch eq 'arm') {
	# Stack protector disabled on ia64, alpha, hppa.
	#   "warning: -fstack-protector not supported for this target"
	# Stack protector disabled on arm (ok on armel).
	#   compiler supports it incorrectly (leads to SEGV)
	$use_feature{stackprotector} = 0;
    }
    if ($cpu =~ /^(?:ia64|hppa|avr32)$/) {
	# relro not implemented on ia64, hppa, avr32.
	$use_feature{relro} = 0;
    }

    # Mask features that might be influenced by other flags.
    if ($flags->{build_options}->has('noopt')) {
      # glibc 2.16 and later warn when using -O0 and _FORTIFY_SOURCE.
      $use_feature{fortify} = 0;
    }

    # Handle logical feature interactions.
    if ($use_feature{relro} == 0) {
	# Disable bindnow if relro is not enabled, since it has no
	# hardening ability without relro and may incur load penalties.
	$use_feature{bindnow} = 0;
    }
    if ($use_feature{stackprotector} == 0) {
	# Disable stackprotectorstrong if stackprotector is disabled.
	$use_feature{stackprotectorstrong} = 0;
    }

    # PIE
    if ($use_feature{pie}) {
	my $flag = '-fPIE';
	$flags->append('CFLAGS', $flag);
	$flags->append('OBJCFLAGS',  $flag);
	$flags->append('OBJCXXFLAGS', $flag);
	$flags->append('FFLAGS', $flag);
	$flags->append('FCFLAGS', $flag);
	$flags->append('CXXFLAGS', $flag);
	$flags->append('GCJFLAGS', $flag);
	$flags->append('LDFLAGS', '-fPIE -pie');
    }

    # Stack protector
    if ($use_feature{stackprotectorstrong}) {
	my $flag = '-fstack-protector-strong';
	$flags->append('CFLAGS', $flag);
	$flags->append('OBJCFLAGS', $flag);
	$flags->append('OBJCXXFLAGS', $flag);
	$flags->append('FFLAGS', $flag);
	$flags->append('FCFLAGS', $flag);
	$flags->append('CXXFLAGS', $flag);
	$flags->append('GCJFLAGS', $flag);
    } elsif ($use_feature{stackprotector}) {
	my $flag = '-fstack-protector --param=ssp-buffer-size=4';
	$flags->append('CFLAGS', $flag);
	$flags->append('OBJCFLAGS', $flag);
	$flags->append('OBJCXXFLAGS', $flag);
	$flags->append('FFLAGS', $flag);
	$flags->append('FCFLAGS', $flag);
	$flags->append('CXXFLAGS', $flag);
	$flags->append('GCJFLAGS', $flag);
    }

    # Fortify Source
    if ($use_feature{fortify}) {
	$flags->append('CPPFLAGS', '-D_FORTIFY_SOURCE=2');
    }

    # Format Security
    if ($use_feature{format}) {
	my $flag = '-Wformat -Werror=format-security';
	$flags->append('CFLAGS', $flag);
	$flags->append('CXXFLAGS', $flag);
	$flags->append('OBJCFLAGS', $flag);
	$flags->append('OBJCXXFLAGS', $flag);
    }

    # Read-only Relocations
    if ($use_feature{relro}) {
	$flags->append('LDFLAGS', '-Wl,-z,relro');
    }

    # Bindnow
    if ($use_feature{bindnow}) {
	$flags->append('LDFLAGS', '-Wl,-z,now');
    }

    # Store the feature usage.
    while (my ($feature, $enabled) = each %use_feature) {
	$flags->set_feature('hardening', $feature, $enabled);
    }
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
