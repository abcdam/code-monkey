#!/usr/bin/perl
#
# An improved launcher that manages resources correctly and handles logs in a sane way
#
use v5.36.0;
use warnings;
use strict;
use YAML::Tiny 'LoadFile';
use MIME::Base64;
use POSIX qw(:sys_wait_h); 
use POSIX qw(setsid strftime);
use Const::Fast;
use File::Basename;
use File::Path qw(make_path);
use Carp;
use Cwd 'abs_path';
use autodie;

#$SIG{CHLD}      = \&zombie_reaper;

# values partly copied from original at https://github.com/open-webui/open-webui/blob/main/backend/start.sh
const my $CONF  => {
    models  => LoadFile('/assets/models.yaml')  // [],
    owebui  => {
        port => $ENV{OWEB_PORT}                 // 8080,
        host => $ENV{OWEB_HOST}                 // 0.0.0.0,
    },
    ollama  => {
        port => $ENV{OLLAMA_PORT}               // 11434,
        host => $ENV{OLLAMA_HOST}               // 0.0.0.0,
    },
    cudalib     => $ENV{LD_LIBRARY_PATH} .= ":/usr/local/lib/python3.11/site-packages/torch/lib:/usr/local/lib/python3.11/site-packages/nvidia/cudnn/lib",
    secret      => sub { $ENV{WEBUI_SECRET_KEY} // generate_secret() },
    timestamp   => strftime("%Y%m%d%H%M", localtime),
    log_dir     => '/var/log/'. fileparse($0, qr/\..*/)
};

{
    package SimpleChain;

    sub new {
        my ($class, $pid) = @_;
        return bless { pid => $pid }, $class;
    }

    sub then {
        my ($self, $next_sub) = @_;
        $next_sub->();  # Start the next process immediately
        return $self;   # Allow further chaining
    }
}

# returns producer + consumer pid
sub create_pipeline {
    my ($producer_cmd, $consumer_cmd) = @_;

    # Create a pipe
    pipe(my $source, my $sink) 
        or die "Failed to create pipe: $!";
    say "create_pipeline1";
    my $writer = fork_then_exec($producer_cmd, undef, $sink);
    say "create_pipeline2";
    close $sink;    # child takes over
    my $reader = fork_then_exec($consumer_cmd, $source, undef);
    say "create_pipeline3";
    close $source;
    return ($writer, $reader);
}

sub fork_then_exec {
    my ($cmd, $fh_in, $fh_out) = @_;

    my $pid = fork() // die "Failed to fork: $!";
    return $pid if $pid;
    
    # Producer will be "orphanized" and becomes adopted by init (pid 1) once $0 exits.
    # -> This ensures that the producer runs as a daemon and that he's solely responsible
    #   for cleaning up his child (the log processor)
    #daemonize() if $fh_out;
    
    # connect pipe
    if ($fh_in) {
        open(STDIN, '<&', $fh_in) or die "Cannot dup input fh: $!";
    } else {
        open(STDOUT, '>&', $fh_out) or die "Cannot dup output fh: $!";
    }

    exec($cmd) or die 'Failed to exec command ' . join(' ', @$cmd) . ": $!";
}

sub daemonize {
    exit if (fork() // die "Failed to fork in daemonize: $!") != 0; # parent exit

    setsid() or die "Failed to create new session: $!";

    # avoid being session leader
    exit if (fork() // die "Failed to fork in daemonize: $!") != 0;

    # best practice to 
    # - give up file descriptors to avoid leaking 
    # - cd to root to not end up in a umounted dir
    chdir '/' or die "Failed to chdir to /: $!";
    open(STDIN,  '</dev/null');
    open(STDOUT, '>/dev/null');
    open(STDERR, '>&STDOUT');
}

# simple fork for short running process
sub fetch_new_models {
    my ($mod_fam, $hash);
    for (@{$CONF->{models}}){
        fork() == 0 and exec 'ollama', 'pull', "$mod_fam:" . (keys %{$hash})[0]
            while  ($mod_fam, $hash) = each %{$_};
    }
}

sub validate_logfile {
    my $path = shift;
    die "logfile exists already at '$path'."
        if -f $path;
    my $dir = dirname($path);
    make_path $dir;
    return $path;
}

sub get_log_processor_cmd {
    my $producer_id = shift;
    my $file = "$CONF->{log_dir}/$CONF->{timestamp}_${producer_id}.log";
    say $file;
    return "/app/backend/log_tee $producer_id " . validate_logfile($file); 
}

sub generate_secret {
    my ($fh, $rand_bytes);
    open $fh, '<', '/dev/urandom'
        or die "Cannot open /dev/urandom: $!";
    read $fh, $rand_bytes, 12;
            
    return encode_base64($rand_bytes);
}

# sub zombie_reaper {
#     do {} while (waitpid(-1, WNOHANG) > 0)
# }
sub zombie_reaper {
    my $pid;
    do {
        $pid = waitpid(-1, WNOHANG);
        if ($pid > 0) {
            my $exit_status = $? >> 8;
            print "Reaped zombie process $pid with exit status $exit_status\n";  # Debug print
        }
    } while ($pid > 0);
}

my ($ollama_prod, $ollama_cons) = create_pipeline("OLLAMA_HOST=$CONF->{ollama}{host} ollama serve", get_log_processor_cmd('ollama'))
    or die("Failed to start ollama and logging daemon");
say "$ollama_prod, $ollama_cons";
# sleep 10;
# fetch_new_models() 
#     or warn "Fetching new models from ollama failed somehwere";

# my $owebui_cmd = join(' ',
#                     "WEBUI_SECRET_KEY=$CONF->{secret}->()",
#                     "uvicorn open_webui.main:app",
#                     "--host $CONF->{owebui}{host}",
#                     "--port $CONF->{owebui}{port}",
#                     "--forwarded-allow-ips '*'");
# my ($owebui_prod, $owebui_cons) = create_pipeline($owebui_cmd, get_log_processor_cmd('owebui')) 
#     or die("Failed to start owebui and logging daemon");