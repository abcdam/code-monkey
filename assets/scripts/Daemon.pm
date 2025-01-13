package Daemon;
use v5.36.0;
use warnings;
use strict;
use POSIX 'close';
use POSIX qw(:sys_wait_h); 
use Carp;

use constant STDIN_NO   => fileno(*STDIN);
use constant STDOUT_NO  => fileno(*STDOUT);
use constant STDERR_NO  => fileno(*STDERR);

sub is {
    my ($class, $conf) = @_;
    croak "Cmd must be set." 
        unless $conf->{cmd};
    my $src_fd  = defined $conf->{src}  ? fileno($conf->{src})  : STDIN_NO;
    my $sink_fd = defined $conf->{sink} ? fileno($conf->{sink}) : STDOUT_NO;
    return bless {
        cmd         => $conf->{cmd},
        src         => $src_fd,
        sink        => $sink_fd,
        is_leader   => $conf->{is_leader}   // 1,  # the original foreparent
        env         => $conf->{env}         // {}, # custom pgid env
        child       => undef,
        pgid        => undef, 
    }, $class;
}

# one child per process, can be chained
sub with_child {
    my ($self, $config) = @_;
    $self->{child} = Daemon->is($config, {is_leader => 0});
    return $self;
}

sub dispatch {
    my ($self) = @_;

    croak "Dispatch can only be called on the process leader" 
        unless $self->{is_leader};
    
    my $pid = fork();
    die "Failed to fork: $!"
        unless defined $pid;

    return {
        pid => $pid,
        killswitch => sub { $self->_childproc_reaper() },
    } if $pid;

    $self->{pgid} = $self->_handle_proc_group();
    $self->_redirect_io();
    $self->_exec();
}

#
# Private
#

sub _childproc_reaper {
    my $self = shift;
    return unless $self->{pgid};
    kill 'TERM', -$self->{pgid}; # kills group
    do {} while waitpid(-1, WNOHANG) > 0;
}

sub _handle_proc_group {
    my $self = shift;
    return getpgrp() unless $self->{is_leader};
    setpgrp(0, 0) or croak "Failed to set process group: $!";
    return $$;
}

sub _redirect_io {
    my ($self) = @_;
    $self->_handle_fd_redirect(*STDIN, $self->{src}, '<&') 
        unless $self->{src} == STDIN_NO;

    $self->_handle_fd_redirect(*STDOUT, $self->{sink}, '>&') 
        unless $self->{sink} == STDOUT_NO;

    $self->_handle_fd_redirect(*STDERR, *STDOUT, '>&');
}

sub _handle_fd_redirect {
    my ($self, $fh, $target_fd, $direction) = @_;
    
    open($fh, $direction, $target_fd) 
        or croak "Failed to redirect filehandle $fh to $target_fd: $!";
    
    close($target_fd) 
        or croak "Failed to close original target fd $target_fd: $!"
        if $target_fd > STDERR_NO; # only for non-std fd
}

sub _exec {
    my $self = shift;
    local %ENV = (%ENV, %{$self->{env}});
    $self->{child}->dispatch() 
        if $self->{child};
    exec @{$self->{cmd}}
        or croak "Failed to exec command" . join(' ', @{$self->{cmd}}) . ": $!";
}


1;