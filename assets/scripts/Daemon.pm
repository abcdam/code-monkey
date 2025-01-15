package Daemon;
use v5.36.0;
use warnings;
use strict;
use POSIX qw(close setsid);
use POSIX qw(:sys_wait_h); 
use Carp;
use File::Path qw(make_path);

use constant STDIN_NO   => fileno(*STDIN);
use constant STDOUT_NO  => fileno(*STDOUT);
use constant STDERR_NO  => fileno(*STDERR);
my $PID_DIR="/tmp";
STDOUT->autoflush(1);

sub _new {
    my $conf = shift;
    croak "uid must be set."
        unless $conf->{uid};
    my $src_fd  = defined $conf->{src}  ? fileno($conf->{src})  : STDIN_NO;
    my $sink_fd = defined $conf->{sink} ? fileno($conf->{sink}) : STDOUT_NO;
    my $pid_dir = make_path($conf->{pid_dir}) ? $conf->{pid_dir} : $PID_DIR;
    return  {
        cmd         => $conf->{cmd},
        src         => $src_fd,
        sink        => $sink_fd,
        is_leader   => $conf->{is_leader}   // 1,  # the original foreparent
        env         => $conf->{env}         // {}, # per daemon scope
        uid         => $conf->{uid},
        children    => {},
        pgid        => undef,
        pid_dir     => $conf->{pid_dir}
    };
}
sub is {
    my ($class, $conf) = @_;
    croak "Cmd must be set. For self-daemonization, use the 'is_myself' constructor." 
        unless $conf->{cmd};
    return bless {
        %{_new($conf)}
    }, $class;
}

sub is_myself {
    my ($class, $conf) = @_;
    croak "cmd detected. Did you want to use the 'is' constructor?"
        if $conf->{cmd};
    return bless {
        %{_new($conf)}
    }, $class;
}

# one child per process, can be chained
sub with_child {
    my ($self, $child_id, $config) = @_;
    croak "Child with ID '$child_id' already exists."
        if exists $self->{children}{$child_id};
    $self->{children}{$child_id} = Daemon->is({%$config, is_leader => 0, uid => $child_id});
    return $self;
}

sub has_child {
    my ($self, $child_id) = @_;
    croak "Child with ID '$child_id' does not exist."
        unless exists $self->{children}{$child_id};
    return $self->{children}{$child_id};
}

sub dispatch {
    my $self = shift;
    croak "Dispatch can only be called on the process leader" 
        unless $self->{is_leader};

    
    if ($self->{cmd}){ # caller does not daemonize, is parent of new proc group
        return $self if _fork();
        setpgrp(0, 0) or croak "Failed to set process group: $!";

    } else { # caller becomes a direct child of init and the root parent
        exit 0 if _fork();
        setsid() or die "Failed to create new session: $!";
        exit 0 if _fork();
    }
    $self->{pgid} = getpgrp();
    $self->_write_gpid_file();
    
    $self->_dispatch();
    return $self;
}

sub childproc_reaper {
    my $self = shift;
    my $pid_file="$self->{pid_dir}/$self->{pgid}_$self->{uid}.pid";
    croak "Only process group leader can terminate group. '$self->{uid}' is not leader."
        unless $self->{is_leader};
    
    say "SIGTERM detected. Cleaning up...";
    STDOUT->flush();

    open my $fh, '<', $pid_file or die "Could not open pidfile '$pid_file': $!";
    chomp(my $pgid = <$fh>);
    close $fh;

    warn "Failed to send SIGTERM to process group $pgid: $!"
        unless kill 'TERM', -$pgid;
    unlink $pid_file;
    waitpid(-1, WNOHANG) while waitpid(-1, WNOHANG) > 0;
}

#
# Private
#
sub _fork {
    die "Failed to fork: $!" unless defined (my $pid = fork());
    return $pid;
}

sub _write_gpid_file {
    my ($self, $pgid) = @_;
    if ($self->{is_leader}) {
        make_path($PID_DIR);
        my $pid_file="$self->{pid_dir}/$self->{pgid}_$self->{uid}.pid";
        $self->_childproc_reaper() if -f $pid_file;
        open my $fh, '>', $pid_file or die "Could not open file '$pid_file': $!";
        print $fh $pgid;
        close $fh;
    }
}

sub _dispatch {
    my $self = shift;
    unless ($self->{is_leader}){
        return $self if _fork();
        say "$self->{uid} minion_lol2";
    }
    
    $self->_redirect_io();
    $self->_exec();
}

sub _redirect_io {
    my ($self) = @_;
    $self->_handle_fd_redirect(*STDIN, $self->{src}, '<&') 
        unless $self->{src} == STDIN_NO;

    $self->_handle_fd_redirect(*STDOUT, $self->{sink}, '>&') 
        unless $self->{sink} == STDOUT_NO;

    $self->_handle_fd_redirect(*STDERR, STDOUT_NO, '>&');
    say "lol3: $self->{uid}";
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
    for (keys %{$self->{children}}){
        say "lol4: $self->{uid}: $self->{children}{$_}{uid}";
        $self->{children}{$_}->_dispatch() ;
    }
    
    return unless $self->{cmd};
    exec @{$self->{cmd}}
        or croak "Failed to exec command" . join(' ', @{$self->{cmd}}) . ": $!";
}


1;