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

package Dpkg::Source::CompressedFile;

use strict;
use warnings;

use Dpkg::Compression;
use Dpkg::Source::Compressor;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error syserr warning subprocerr);
use POSIX;

# Object methods
sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = {
	"compression" => "auto"
    };
    bless $self, $class;
    $self->{"compressor"} = Dpkg::Source::Compressor->new();
    $self->{"add_comp_ext"} = $args{"add_compression_extension"} ||
	    $args{"add_comp_ext"} || 0;
    $self->{"allow_sigpipe"} = 0;
    if (exists $args{"filename"}) {
	$self->set_filename($args{"filename"});
    }
    if (exists $args{"compression"}) {
	$self->set_compression($args{"compression"});
    }
    if (exists $args{"compression_level"}) {
	$self->set_compression_level($args{"compression_level"});
    }
    return $self;
}

sub reset {
    my ($self) = @_;
    %{$self} = ();
}

sub set_compression {
    my ($self, $method) = @_;
    if ($method ne "none" and $method ne "auto") {
	$self->{"compressor"}->set_compression($method);
    }
    $self->{"compression"} = $method;
}

sub set_compression_level {
    my ($self, $level) = @_;
    $self->{"compressor"}->set_compression_level($level);
}

sub set_filename {
    my ($self, $filename, $add_comp_ext) = @_;
    $self->{"filename"} = $filename;
    # Automatically add compression extension to filename
    if (defined($add_comp_ext)) {
	$self->{"add_comp_ext"} = $add_comp_ext;
    }
    if ($self->{"add_comp_ext"} and $filename =~ /\.$comp_regex$/) {
	warning("filename %s already has an extension of a compressed file " .
	        "and add_comp_ext is active", $filename);
    }
}

sub get_filename {
    my $self = shift;
    my $comp = $self->{"compression"};
    if ($self->{'add_comp_ext'}) {
	if ($comp eq "auto") {
	    error("automatic detection of compression is " .
	          "incompatible with add_comp_ext");
	} elsif ($comp eq "none") {
	    return $self->{"filename"};
	} else {
	    return $self->{"filename"} . "." . $comp_ext{$comp};
	}
    } else {
	return $self->{"filename"};
    }
}

sub use_compression {
    my ($self, $update) = @_;
    my $comp = $self->{"compression"};
    if ($comp eq "none") {
	return 0;
    } elsif ($comp eq "auto") {
	$comp = get_compression_from_filename($self->get_filename());
	$self->{"compressor"}->set_compression($comp) if $comp;
    }
    return $comp;
}

sub open_for_write {
    my ($self) = @_;
    my $handle;
    if ($self->use_compression()) {
	$self->{'compressor'}->compress(from_pipe => \$handle,
		to_file => $self->get_filename());
    } else {
	open($handle, '>', $self->get_filename()) ||
		syserr(_g("cannot write %s"), $self->get_filename());
    }
    return $handle;
}

sub open_for_read {
    my ($self) = @_;
    my $handle;
    if ($self->use_compression()) {
	$self->{'compressor'}->uncompress(to_pipe => \$handle,
		from_file => $self->get_filename());
        $self->{'allow_sigpipe'} = 1;
    } else {
	open($handle, '<', $self->get_filename()) ||
		syserr(_g("cannot read %s"), $self->get_filename());
    }
    return $handle;
}

sub cleanup_after_open {
    my ($self) = @_;
    $self->{"compressor"}->wait_end_process(nocheck => $self->{'allow_sigpipe'});
    if ($self->{'allow_sigpipe'}) {
        unless (($? == 0) || (WIFSIGNALED($?) && (WTERMSIG($?) == SIGPIPE))) {
            subprocerr($self->{"compressor"}{"cmdline"});
        }
    }
}

1;
