package Daemon;
use v5.36.0;
use warnings;
use strict;
use POSIX 'close';
use POSIX qw(:sys_wait_h); 

sub is {
    my ($class, $config, $is_root) = @_;
    return bless {
        cmd     => $config->{cmd},
        src     => fileno($config->{src}    // *STDIN) ,
        sink    => fileno($config->{sink}   // *STDOUT),
        child   => undef,                           # recursive child ref
        is_root => $is_root                 // 1,   # the original foreparent
        env     => $config->{env}           //{},   # custom pgid env
        pgid    => undef, 
    }, $class;
}

# one child per process, can be chained
sub with_child {
    my ($self, $config) = @_;
    $self->{child} = Daemon->is($config, 0);
    return $self;
}

sub childproc_reaper {
    my ($self) = @_;
    if ($self->{pgid}) {
        # kill whole group and wait for confirmation
        kill 'TERM', -$self->{pgid};
        do {} while (waitpid(-1, WNOHANG) > 0);
    }
    exit;
}

sub dispatch {
    my ($self) = @_;

    # outer dispatch is only callable on pgid leader
    die "Dispatch can only be called on the root parent" 
        if $self->{is_root} && !$self->{cmd};

    my $pid = fork() // die "Failed to fork: $!";
    return {
        pid => $pid,
        killswitch => sub { $self->childproc_reaper() },
    } if ($pid);

    if ($self->{is_root}) {
        setpgrp(0, 0) or die "Failed to create new process group: $!";
        $self->{pgid} = $$;
    } else {
        $self->{pgid} = getpgrp(); # inherit if child
    }
    #
    # PIPE	REDIRECTION
    #
    if ($self->{src} != fileno(*STDIN)) {
        open(STDIN, '<&', $self->{src}) || die "Cannot dup input fh ($self->{src}): $!";
        close($self->{src}); # close original after duplication
    }
    if ($self->{sink} != fileno(*STDOUT)) {
        open(STDOUT, '>&', $self->{sink}) || die "Cannot dup output fh ($self->{sink}): $!";
        close($self->{sink}); 
    }
    open(STDERR, '>&', STDOUT) or die "Failed to redirect STDERR to STDOUT: $!";

    # local scope for custom env vars that shouldn't be exposed to parents
    # if current proc has a child, dispatch, otherwise replace perl proc with cmd proc
    {
        local %ENV = (%ENV, %{$self->{env}});
        $self->{child}->dispatch() if ($self->{child});
        exec(@{$self->{cmd}}) or die "Failed to exec command @{$self->{cmd}}: $!";
    }
}
1;