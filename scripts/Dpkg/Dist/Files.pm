# Copyright © 2014 Guillem Jover <guillem@debian.org>
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

package Dpkg::Dist::Files;

use strict;
use warnings;

our $VERSION = '0.01';

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

use parent qw(Dpkg::Interface::Storable);

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
        options => [],
        files => {},
        order => [],
    };
    foreach my $opt (keys %opts) {
        $self->{$opt} = $opts{$opt};
    }
    bless $self, $class;

    return $self;
}

sub parse {
    my ($self, $fh, $desc) = @_;
    my $count = 0;

    local $_;
    binmode $fh;

    while (<$fh>) {
        chomp;

        my %file;

        if (m/^(([-+.0-9a-z]+)_([^_]+)_([-\w]+)\.([a-z0-9.]+)) (\S+) (\S+)$/) {
            $file{filename} = $1;
            $file{package} = $2;
            $file{version} = $3;
            $file{arch} = $4;
            $file{package_type} = $5;
            $file{section} = $6;
            $file{priority} = $7;
        } elsif (m/^([-+.,_0-9a-zA-Z]+) (\S+) (\S+)$/) {
            $file{filename} = $1;
            $file{section} = $2;
            $file{priority} = $3;
        } else {
            error(g_('badly formed line in files list file, line %d'), $.);
        }

        if (defined $self->{files}->{$file{filename}}) {
            warning(g_('duplicate files list entry for file %s (line %d)'),
                    $file{filename}, $.);
        } else {
            $count++;
            $self->{files}->{$file{filename}} = \%file;
            push @{$self->{order}}, $file{filename};
        }
    }

    return $count;
}

sub get_files {
    my $self = shift;

    return map { $self->{files}->{$_} } @{$self->{order}};
}

sub get_file {
    my ($self, $filename) = @_;

    return $self->{files}->{$filename};
}

sub add_file {
    my ($self, $filename, $section, $priority) = @_;

    # XXX: Ideally we'd need to parse the filename, to match the behaviour
    # on parse(), and initialize the other attributes, although no code is
    # in need of this for now, at least in dpkg-dev.

    if (not defined $self->{files}->{$filename}) {
        push @{$self->{order}}, $filename;
    }

    $self->{files}->{$filename} = {
        filename => $filename,
        section => $section,
        priority => $priority,
    };
}

sub del_file {
    my ($self, $filename) = @_;

    delete $self->{files}->{$filename};

    @{$self->{order}} = grep { $_ ne $filename } @{$self->{order}};
}

sub output {
    my ($self, $fh) = @_;
    my $str = '';

    binmode $fh if defined $fh;

    foreach my $filename (@{$self->{order}}) {
        my $file = $self->{files}->{$filename};
        my $entry = "$filename $file->{section} $file->{priority}\n";

        print { $fh } $entry if defined $fh;
        $str .= $entry;
    }

    return $str;
}

1;
