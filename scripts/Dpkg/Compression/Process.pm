# Copyright © 2008-2010 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::Compression::Process;

use strict;
use warnings;

use Dpkg::Compression;
use Dpkg::Gettext;
use Dpkg::IPC;
use Dpkg::ErrorHandling;

use POSIX;

# Object methods
sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    $self->set_compression($args{"compression"} || compression_get_default());
    $self->set_compression_level($args{"compression_level"} ||
	    compression_get_default_level());
    return $self;
}

sub set_compression {
    my ($self, $method) = @_;
    error(_g("%s is not a supported compression method"), $method)
	    unless compression_is_supported($method);
    $self->{"compression"} = $method;
}

sub set_compression_level {
    my ($self, $level) = @_;
    error(_g("%s is not a compression level"), $level)
	    unless compression_is_valid_level($level);
    $self->{"compression_level"} = $level;
}

sub get_compress_cmdline {
    my ($self) = @_;
    my @prog = (compression_get_property($self->{"compression"}, "comp_prog"));
    my $level = "-" . $self->{"compression_level"};
    $level = "--" . $self->{"compression_level"}
	    if $self->{"compression_level"} =~ m/best|fast/;
    push @prog, $level;
    return @prog;
}

sub get_uncompress_cmdline {
    my ($self) = @_;
    return (compression_get_property($self->{"compression"}, "decomp_prog"));
}

sub _sanity_check {
    my ($self, %opts) = @_;
    # Check for proper cleaning before new start
    error(_g("Dpkg::Compression::Process can only start one subprocess at a time"))
	    if $self->{"pid"};
    # Check options
    my $to = my $from = 0;
    foreach (qw(file handle string pipe)) {
        $to++ if $opts{"to_$_"};
        $from++ if $opts{"from_$_"};
    }
    internerr("exactly one to_* parameter is needed") if $to != 1;
    internerr("exactly one from_* parameter is needed") if $from != 1;
    return %opts;
}

sub compress {
    my $self = shift;
    my %opts = $self->_sanity_check(@_);
    my @prog = $self->get_compress_cmdline();
    $opts{"exec"} = \@prog;
    $self->{"cmdline"} = "@prog";
    $self->{"pid"} = fork_and_exec(%opts);
    delete $self->{"pid"} if $opts{"to_string"}; # wait_child already done
}

sub uncompress {
    my $self = shift;
    my %opts = $self->_sanity_check(@_);
    my @prog = $self->get_uncompress_cmdline();
    $opts{"exec"} = \@prog;
    $self->{"cmdline"} = "@prog";
    $self->{"pid"} = fork_and_exec(%opts);
    delete $self->{"pid"} if $opts{"to_string"}; # wait_child already done
}

sub wait_end_process {
    my ($self, %opts) = @_;
    $opts{"cmdline"} ||= $self->{"cmdline"};
    wait_child($self->{"pid"}, %opts) if $self->{'pid'};
    delete $self->{"pid"};
    delete $self->{"cmdline"};
}

1;
