# Copyright 2008 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Source::Compressor;

use strict;
use warnings;

use Dpkg::Compression;
use Dpkg::Gettext;
use Dpkg::IPC;
use Dpkg::ErrorHandling qw(error syserr warning);

use POSIX;

our $default_compression = "gzip";
our $default_compression_level = 9;

# Class methods
sub set_default_compression {
    my ($self, $method) = @_;
    error(_g("%s is not a supported compression"), $method)
	    unless $comp_supported{$method};
    $default_compression = $method;
}

sub set_default_compression_level {
    my ($self, $level) = @_;
    error(_g("%s is not a compression level"), $level)
	    unless $level =~ /^([1-9]|fast|best)$/;
    $default_compression_level = $level;
}

# Object methods
sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = {
	"compression" => $default_compression,
	"compression_level" => $default_compression_level,
    };
    bless $self, $class;
    if (exists $args{"compression"}) {
	$self->set_compression($args{"compression"});
    }
    if (exists $args{"compression_level"}) {
	$self->set_compression_level($args{"compression_level"});
    }
    if (exists $args{"filename"}) {
	$self->set_filename($args{"filename"});
    }
    if (exists $args{"uncompressed_filename"}) {
	$self->set_uncompressed_filename($args{"uncompressed_filename"});
    }
    if (exists $args{"compressed_filename"}) {
	$self->set_compressed_filename($args{"compressed_filename"});
    }
    return $self;
}

sub set_compression {
    my ($self, $method) = @_;
    error(_g("%s is not a supported compression method"), $method)
	    unless $comp_supported{$method};
    $self->{"compression"} = $method;
}

sub set_compression_level {
    my ($self, $level) = @_;
    error(_g("%s is not a compression level"), $level)
	    unless $level =~ /^([1-9]|fast|best)$/;
    $self->{"compression_level"} = $level;
}

sub set_filename {
    my ($self, $filename) = @_;
    my $comp = get_compression_from_filename($filename);
    if ($comp) {
	$self->set_compression($comp);
	$self->set_compressed_filename($filename);
    } else {
	error(_g("unknown compression type on file %s"), $filename);
    }
}

sub set_compressed_filename {
    my ($self, $filename) = @_;
    $self->{"compressed_filename"} = $filename;
}

sub set_uncompressed_filename {
    my ($self, $filename) = @_;
    warning(_g("uncompressed filename %s has an extension of a compressed file"),
	    $filename) if $filename =~ /\.$comp_regex$/;
    $self->{"uncompressed_filename"} = $filename;
}

sub get_filename {
    my $self = shift;
    if ($self->{"compressed_filename"}) {
	return $self->{"compressed_filename"};
    } elsif ($self->{"uncompressed_filename"}) {
	return $self->{"uncompressed_filename"} . "." .
	       $comp_ext{$self->{"compression"}};
    }
}

sub get_compress_cmdline {
    my ($self) = @_;
    my @prog = ($comp_prog{$self->{"compression"}});
    my $level = "-" . $self->{"compression_level"};
    $level = "--" . $self->{"compression_level"}
	    if $self->{"compression_level"} =~ m/best|fast/;
    push @prog, $level;
    return @prog;
}

sub get_uncompress_cmdline {
    my ($self) = @_;
    return ($comp_decomp_prog{$self->{"compression"}});
}

sub compress {
    my ($self, %opts) = @_;
    unless($opts{"from_file"} or $opts{"from_handle"} or $opts{"from_pipe"}) {
	error("compress() needs a from_{file,handle,pipe} parameter");
    }
    unless($opts{"to_file"} or $opts{"to_handle"} or $opts{"to_pipe"}) {
	$opts{"to_file"} = $self->get_filename();
    }
    error(_g("Dpkg::Source::Compressor can only start one subprocess at a time"))
	    if $self->{"pid"};
    my @prog = $self->get_compress_cmdline();
    $opts{"exec"} = \@prog;
    $self->{"cmdline"} = "@prog";
    $self->{"pid"} = fork_and_exec(%opts);
}

sub uncompress {
    my ($self, %opts) = @_;
    unless($opts{"from_file"} or $opts{"from_handle"} or $opts{"from_pipe"}) {
	$opts{"from_file"} = $self->get_filename();
    }
    unless($opts{"to_file"} or $opts{"to_handle"} or $opts{"to_pipe"}) {
	error("uncompress() needs a to_{file,handle,pipe} parameter");
    }
    error(_g("Dpkg::Source::Compressor can only start one subprocess at a time"))
	    if $self->{"pid"};
    my @prog = $self->get_uncompress_cmdline();
    $self->{"cmdline"} = "@prog";
    $opts{"exec"} = \@prog;
    $self->{"pid"} = fork_and_exec(%opts);
}

sub wait_end_process {
    my ($self) = @_;
    wait_child($self->{"pid"}, cmdline => $self->{"cmdline"});
    delete $self->{"pid"};
    delete $self->{"cmdline"};
}

1;
