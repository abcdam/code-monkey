#!/usr/bin/env perl
#
# An improved launcher that manages resources correctly and handles logs in a sane way.
#
## Process tree:
##  root@762b3982446a:/app/backend# pstree --ascii --arguments --show-pgids
##    perl,1 puppeteer.pl
##      |-perl,7 /app/backend/log_tee ollama /var/log/puppeteer/202501101648_ollama.log
##      |   `-ollama,7 serve
##      |       `-15*[{ollama},7]
##      `-perl,8 /app/backend/log_tee owebui /var/log/puppeteer/202501101648_owebui.log
##          `-uvicorn,8 /usr/local/bin/uvicorn open_webui.main:app --host 0.0.0.0 --port 8080 --forwarded-allow-ips *
##              `-69*[{uvicorn},8]

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
use lib './lib';
use Daemon;

$SIG{TERM} = $SIG{INT} = \&reaper;
my @KILL_SWITCHES = ();

$ENV{LD_LIBRARY_PATH} .= ":/usr/local/lib/python3.11/site-packages/torch/lib:/usr/local/lib/python3.11/site-packages/nvidia/cudnn/lib";
# values partly copied from original at https://github.com/open-webui/open-webui/blob/main/backend/start.sh
const my $CONF  => {
    models  => LoadFile('/assets/configs/models.yaml')  // [],
    owebui  => {
        port => $ENV{OWEB_PORT}                 // 8080,
        host => $ENV{OWEB_HOST}                 // "0.0.0.0",
    },
    ollama  => {
        port => $ENV{OLLAMA_PORT}               // 11434,
        host => $ENV{OLLAMA_HOST}               // "0.0.0.0",
    },
    secret      => sub { $ENV{WEBUI_SECRET_KEY} // generate_secret() },
    timestamp   => strftime("%Y%m%d%H%M", localtime),
    log_dir     => '/var/log/'. fileparse($0, qr/\..*/)
};

sub run {
    my ($producer_cmd, $consumer_cmd, $env) = @_;
    open(my $NULL_IN, '<', '/dev/null') or die "Cannot open /dev/null for reading: $!";
    pipe(my $source, my $sink) or die "Failed to create pipe: $!";

    # Configure the process chain
    my $producer = {
        cmd     => $producer_cmd, 
        src     => $NULL_IN, 
        sink    => $sink, 
        env     => $env 
    };
    my $consumer = {
        cmd => $consumer_cmd, 
        src => $source 
    };
    # the order is reversed to make the producer and his children inherit all filehandles from the consumer
    return Daemon->is($consumer)
                    ->with_child($producer)
                    ->dispatch();
}

sub fetch_new_models {
    my ($mod_fam, $hash);
    for (@{$CONF->{models}}){
        fork() == 0 and exec 'ollama', 'pull', "$mod_fam:" . (keys %{$hash})[0]
            while  ($mod_fam, $hash) = each %{$_};
    }
}

sub validate_logfile {
    my $path = shift;
    my $dir = dirname($path);
    make_path $dir;
    return $path;
}

sub get_log_processor_cmd {
    my $producer_id = shift;
    my $file = "$CONF->{log_dir}/$CONF->{timestamp}_${producer_id}.log";
    say $file;
    return ['/app/backend/log_tee', "$producer_id", validate_logfile($file)]; 
}

sub generate_secret {
    my ($fh, $rand_bytes);
    open $fh, '<', '/dev/urandom'
        or die "Cannot open /dev/urandom: $!";
    read $fh, $rand_bytes, 12;
            
    return encode_base64($rand_bytes);
}

sub reaper {
    print "SIGTERM detected. Cleaning up...\n";
    STDOUT->flush();
    $_->() for (@KILL_SWITCHES);
    exit 0;
}

my @args = ();
push @args, 
    ['ollama', 'serve'], 
    get_log_processor_cmd('ollama'), 
    {OLLAMA_HOST => $CONF->{ollama}{host}};

push @KILL_SWITCHES, run(@args)->{killswitch};
@args = ();

my $owebui_cmd = [
                    "uvicorn",
                    "open_webui.main:app",
                    "--host",
                    "$CONF->{owebui}{host}",
                    "--port",
                    "$CONF->{owebui}{port}",
                    "--forwarded-allow-ips",
                    '*'
];
push @args, 
    $owebui_cmd, 
    get_log_processor_cmd('owebui'), 
    {WEBUI_SECRET_KEY => $CONF->{secret}->()};
push @KILL_SWITCHES, run(@args)->{killswitch};

do {sleep 2} while(waitpid(-1, WNOHANG) != -1);