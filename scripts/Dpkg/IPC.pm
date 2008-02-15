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

sub fork_and_exec {
    my (%opts) = @_;
    $opts{"close_in_child"} ||= [];
    error("exec parameter is mandatory in fork_and_exec()") unless $opts{"exec"};
    my @prog;
    if (ref($opts{"exec"}) =~ /ARRAY/) {
	push @prog, @{$opts{"exec"}};
    } elsif (not ref($opts{"exec"})) {
	push @prog, $opts{"exec"};
    } else {
	error(_g("invalid exec parameter in fork_and_exec()"));
    }
    my ($from_string_pipe, $to_string_pipe);
    if ($opts{"to_string"}) {
	$opts{"to_pipe"} = \$to_string_pipe;
	$opts{"wait_child"} = 1;
    }
    if ($opts{"from_string"}) {
	$opts{"from_pipe"} = \$from_string_pipe;
    }
    # Create pipes if needed
    my ($input_pipe, $output_pipe);
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
    # Fork and exec
    my $pid = fork();
    syserr(_g("fork for %s"), "@prog") unless defined $pid;
    if (not $pid) {
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
	# Close some inherited filehandles
        close($_) foreach (@{$opts{"close_in_child"}});
	# Execute the program
	exec({ $prog[0] } @prog) or syserr(_g("exec %s"), "@prog");
    }
    # Close handle that we can't use any more
    close($opts{"from_handle"}) if exists $opts{"from_handle"};
    close($opts{"to_handle"}) if exists $opts{"to_handle"};

    if ($opts{"from_string"}) {
	print $from_string_pipe ${$opts{"from_string"}};
	close($from_string_pipe);
    }
    if ($opts{"to_string"}) {
	local $/ = undef;
	${$opts{"to_string"}} = readline($to_string_pipe);
    }
    if ($opts{"wait_child"}) {
	wait_child($pid, cmdline => "@prog");
	return 1;
    }

    return $pid;
}

sub wait_child {
    my ($pid, %opts) = @_;
    $opts{"cmdline"} ||= _g("child process");
    error(_g("no PID set, cannot wait end of process")) unless $pid;
    $pid == waitpid($pid, 0) or syserr(_g("wait for %s"), $opts{"cmdline"});
    subprocerr($opts{"cmdline"}) if $?;
}

1;
