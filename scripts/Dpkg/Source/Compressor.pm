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
    # Identify compression from filename
    my $found = 0;
    foreach my $comp (@comp_supported) {
	if ($filename =~ /^(.*)\.\Q$comp_ext{$comp}\E$/) {
	    $found = 1;
	    $self->set_compression($comp);
	    $self->set_uncompressed_filename($1);
	    last;
	}
    }
    error(_g("unknown compression type on file %s"), $filename) unless $found;
}

sub get_filename {
    my $self = shift;
    return $self->{"uncompressed_filename"} . "." .
	   $comp_ext{$self->{"compression"}};
}

sub set_uncompressed_filename {
    my ($self, $filename) = @_;
    warning(_g("uncompressed filename %s has an extension of a compressed file"),
	    $filename) if $filename =~ /\.$comp_regex$/;
    $self->{"uncompressed_filename"} = $filename;
}

sub wait_end_process {
    my ($self) = @_;
    wait_child($self->{"pid"}, cmdline => $self->{"cmdline"});
    delete $self->{"pid"};
    delete $self->{"cmdline"};
}

sub close_in_child {
    my ($self, $fd) = @_;
    if (not $self->{"close_in_child"}) {
	$self->{"close_in_child"} = [];
    }
    push @{$self->{"close_in_child"}}, $fd;
}

sub get_compress_cmdline {
    my ($self) = @_;
    # Define the program invocation
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

sub compress_from_fd_to_file {
    my ($self, $fd, $filename) = @_;
    $filename ||= $self->get_filename();
    error(_g("Dpkg::Source::Compressor can only start one subprocess at a time"))
	    if $self->{"pid"};
    my @prog = $self->get_compress_cmdline();
    $self->{"cmdline"} = "@prog";
    $self->{"pid"} = fork_and_exec(
	    'exec' => \@prog,
	    from_handle => $fd,
	    to_file => $filename,
	    close_in_child => $self->{"close_in_child"}
    );
}

sub compress_from_pipe_to_file {
    my ($self, $filename) = @_;
    $filename ||= $self->get_filename();
    # Open pipe
    pipe(my $read_fh, my $write_fh) ||
	    syserr(_g("pipe for %s"), $comp_prog{$self->{"compression"}});
    binmode($write_fh);
    $self->close_in_child($write_fh);
    # Start the process
    $self->compress_from_fd_to_file($read_fh, $filename);
    return $write_fh;
}

sub uncompress_from_file_to_fd {
    my ($self, $filename, $fd) = @_;
    $filename ||= $self->get_filename();
    error(_g("Dpkg::Source::Compressor can only start one subprocess at a time"))
	    if $self->{"pid"};
    my @prog = $self->get_uncompress_cmdline();
    $self->{"cmdline"} = "@prog";
    $self->{"pid"} = fork_and_exec(
	    'exec' => \@prog,
	    from_file => $filename,
	    to_handle => $fd,
	    close_in_child => $self->{"close_in_child"}
    );
}

sub uncompress_from_file_to_pipe {
    my ($self, $filename) = @_;
    $filename ||= $self->get_filename();
    # Open output pipe
    pipe(my $read_fh, my $write_fh) ||
	    syserr(_g("pipe for %s"), $self->{"cmdline"});
    binmode($read_fh);
    $self->close_in_child($read_fh);
    # Start the process
    $self->uncompress_from_file_to_fd($filename, $write_fh);
    # Return the read side of the pipe
    return $read_fh;
}

1;
