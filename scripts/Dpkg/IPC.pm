# Copyright 2008 Raphaël Hertzog <hertzog@debian.org>
# Copyright 2008 Frank Lichtenheld <djpig@debian.org>

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

package Dpkg::IPC;

use strict;
use warnings;

use Dpkg::ErrorHandling qw(error syserr subprocerr);
use Dpkg::Gettext;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(fork_and_exec wait_child);

=head1 NAME

Dpkg::IPC - helper functions for IPC

=head1 DESCRIPTION

Dpkg::IPC offers helper functions to allow you to execute
other programs in an easy, yet flexible way, while hiding
all the gory details of IPC (Inter-Process Communication)
from you.

=head1 METHODS

=over 4

=item fork_and_exec

Creates a child process and executes another program in it.
The arguments are interpreted as a hash of options, specifying
how to handle the in and output of the program to execute.
Returns the pid of the child process (unless the wait_child
option was given).

Any error will cause the function to exit with one of the
Dpkg::ErrorHandling functions.

Options:

=over 4

=item exec

Can be either a scalar, i.e. the name of the program to be
executed, or an array reference, i.e. the name of the program
plus additional arguments. Note that the program will never be
executed via the shell, so you can't specify additional arguments
in the scalar string and you can't use any shell facilities like
globbing.

Mandatory Option.

=item from_file, to_file, error_to_file

Filename as scalar. Standard input/output/error of the
child process will be redirected to the file specifed.

=item from_handle, to_handle, error_to_handle

Filehandle. Standard input/output/error of the child process will be
dup'ed from the handle.

=item from_pipe, to_pipe, error_to_pipe

Scalar reference. A pipe will be opened for each of the two options
and either the reading (C<to_pipe> and C<error_to_pipe>) or the writing
end (C<from_pipe>) will be returned in the referenced scalar. Standard
input/output/error of the child process will be dup'ed to the other ends
of the pipes.

=item from_string, to_string, error_to_string

Scalar reference. Standard input/output/error of the child
process will be redirected to the string given as reference. Note
that it wouldn't be strictly necessary to use a scalar reference
for C<from_string>, as the string is not modified in any way. This was
chosen only for reasons of symmetry with C<to_string> and
C<error_to_string>. C<to_string> and C<error_to_string> imply the
C<wait_child> option.

=item wait_child

Scalar. If containing a true value, wait_child() will be called before
returning. The return value will of fork_and_exec() will be a true value,
but not the pid.

=item chdir

Scalar. The child process will chdir in the indicated directory before
calling exec.

=item env

Hash reference. The child process will populate %ENV with the items of the
hash before calling exec. This allows exporting environment variables.

=item delete_env

Array reference. The child process will remove all environment variables
listed in the array before calling exec.

=back

=cut

sub _sanity_check_opts {
    my (%opts) = @_;

    error("exec parameter is mandatory in fork_and_exec()")
	unless $opts{"exec"};

    my $to = my $error_to = my $from = 0;
    foreach (qw(file handle string pipe)) {
	$to++ if $opts{"to_$_"};
	$error_to++ if $opts{"error_to_$_"};
	$from++ if $opts{"from_$_"};
    }
    error("not more than one of to_* parameters is allowed")
	if $to > 1;
    error("not more than one of error_to_* parameters is allowed")
	if $error_to > 1;
    error("not more than one of from_* parameters is allowed")
	if $from > 1;

    foreach (qw(to_string error_to_string from_string
                to_pipe error_to_pipe from_pipe))
    {
	if (exists $opts{$_} and
	    (!ref($opts{$_}) or ref($opts{$_}) ne 'SCALAR')) {
	    error("parameter $_ must be a scalar reference");
	}
    }

    if (exists $opts{"env"} and ref($opts{"env"}) ne 'HASH') {
	error("parameter env must be a hash reference");
    }

    if (exists $opts{"delete_env"} and ref($opts{"delete_env"}) ne 'ARRAY') {
	error("parameter delete_env must be an array reference");
    }

    return %opts;
}

sub fork_and_exec {
    my (%opts) = _sanity_check_opts(@_);
    $opts{"close_in_child"} ||= [];
    my @prog;
    if (ref($opts{"exec"}) =~ /ARRAY/) {
	push @prog, @{$opts{"exec"}};
    } elsif (not ref($opts{"exec"})) {
	push @prog, $opts{"exec"};
    } else {
	error(_g("invalid exec parameter in fork_and_exec()"));
    }
    my ($from_string_pipe, $to_string_pipe, $error_to_string_pipe);
    if ($opts{"to_string"}) {
	$opts{"to_pipe"} = \$to_string_pipe;
	$opts{"wait_child"} = 1;
    }
    if ($opts{"error_to_string"}) {
	$opts{"error_to_pipe"} = \$error_to_string_pipe;
	$opts{"wait_child"} = 1;
    }
    if ($opts{"from_string"}) {
	$opts{"from_pipe"} = \$from_string_pipe;
    }
    # Create pipes if needed
    my ($input_pipe, $output_pipe, $error_pipe);
    if ($opts{"from_pipe"}) {
	pipe($opts{"from_handle"}, $input_pipe) ||
		syserr(_g("pipe for %s"), "@prog");
	${$opts{"from_pipe"}} = $input_pipe;
	push @{$opts{"close_in_child"}}, $input_pipe;
    }
    if ($opts{"to_pipe"}) {
	pipe($output_pipe, $opts{"to_handle"}) ||
		syserr(_g("pipe for %s"), "@prog");
	${$opts{"to_pipe"}} = $output_pipe;
	push @{$opts{"close_in_child"}}, $output_pipe;
    }
    if ($opts{"error_to_pipe"}) {
	pipe($error_pipe, $opts{"error_to_handle"}) ||
		syserr(_g("pipe for %s"), "@prog");
	${$opts{"error_to_pipe"}} = $error_pipe;
	push @{$opts{"close_in_child"}}, $error_pipe;
    }
    # Fork and exec
    my $pid = fork();
    syserr(_g("fork for %s"), "@prog") unless defined $pid;
    if (not $pid) {
	# Define environment variables
	if ($opts{"env"}) {
	    foreach (keys %{$opts{"env"}}) {
		$ENV{$_} = $opts{"env"}{$_};
	    }
	}
	if ($opts{"delete_env"}) {
	    delete $ENV{$_} foreach (@{$opts{"delete_env"}});
	}
	# Change the current directory
	if ($opts{"chdir"}) {
	    chdir($opts{"chdir"}) || syserr(_g("chdir to %s"), $opts{"chdir"});
	}
	# Redirect STDIN if needed
	if ($opts{"from_file"}) {
	    open(STDIN, "<", $opts{"from_file"}) ||
		syserr(_g("cannot open %s"), $opts{"from_file"});
	} elsif ($opts{"from_handle"}) {
	    open(STDIN, "<&", $opts{"from_handle"}) || syserr(_g("reopen stdin"));
	    close($opts{"from_handle"}); # has been duped, can be closed
	}
	# Redirect STDOUT if needed
	if ($opts{"to_file"}) {
	    open(STDOUT, ">", $opts{"to_file"}) ||
		syserr(_g("cannot write %s"), $opts{"to_file"});
	} elsif ($opts{"to_handle"}) {
	    open(STDOUT, ">&", $opts{"to_handle"}) || syserr(_g("reopen stdout"));
	    close($opts{"to_handle"}); # has been duped, can be closed
	}
	# Redirect STDERR if needed
	if ($opts{"error_to_file"}) {
	    open(STDERR, ">", $opts{"error_to_file"}) ||
		syserr(_g("cannot write %s"), $opts{"error_to_file"});
	} elsif ($opts{"error_to_handle"}) {
	    open(STDERR, ">&", $opts{"error_to_handle"}) || syserr(_g("reopen stdout"));
	    close($opts{"error_to_handle"}); # has been duped, can be closed
	}
	# Close some inherited filehandles
	close($_) foreach (@{$opts{"close_in_child"}});
	# Execute the program
	exec({ $prog[0] } @prog) or syserr(_g("exec %s"), "@prog");
    }
    # Close handle that we can't use any more
    close($opts{"from_handle"}) if exists $opts{"from_handle"};
    close($opts{"to_handle"}) if exists $opts{"to_handle"};
    close($opts{"error_to_handle"}) if exists $opts{"error_to_handle"};

    if ($opts{"from_string"}) {
	print $from_string_pipe ${$opts{"from_string"}};
	close($from_string_pipe);
    }
    if ($opts{"to_string"}) {
	local $/ = undef;
	${$opts{"to_string"}} = readline($to_string_pipe);
    }
    if ($opts{"error_to_string"}) {
	local $/ = undef;
	${$opts{"error_to_string"}} = readline($error_to_string_pipe);
    }
    if ($opts{"wait_child"}) {
	wait_child($pid, cmdline => "@prog");
	return 1;
    }

    return $pid;
}


=item wait_child

Takes as first argument the pid of the process to wait for.
Remaining arguments are taken as a hash of options. Returns
nothing. Fails if the child has been ended by a signal or
if it exited non-zero.

Options:

=over 4

=item cmdline

String to identify the child process in error messages.
Defaults to "child process".

=item nocheck

If true do not check the return status of the child (and thus
do not fail it it has been killed or if it exited with a
non-zero return code).

=back

=cut

sub wait_child {
    my ($pid, %opts) = @_;
    $opts{"cmdline"} ||= _g("child process");
    error(_g("no PID set, cannot wait end of process")) unless $pid;
    $pid == waitpid($pid, 0) or syserr(_g("wait for %s"), $opts{"cmdline"});
    unless ($opts{"nocheck"}) {
	subprocerr($opts{"cmdline"}) if $?;
    }
}

1;
__END__

=back

=head1 AUTHORS

Written by Raphaël Hertzog <hertzog@debian.org> and
Frank Lichtenheld <djpig@debian.org>.

=head1 SEE ALSO

Dpkg, Dpkg::ErrorHandling
