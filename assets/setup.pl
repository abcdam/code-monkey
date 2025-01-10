#!/usr/bin/perl
use v5.36.0;
use YAML::Tiny 'LoadFile';
use MIME::Base64;
use autodie;
use IPC::Run qw(run);
use POSIX qw(:sys_wait_h); 
use POSIX qw(setsid); 

sub zombie_reaper {
    do {} while (waitpid(-1, WNOHANG) > 0)
}
$SIG{CHLD} = \&zombie_reaper;


# partly copied from https://github.com/open-webui/open-webui/blob/main/backend/start.sh
$ENV{LD_LIBRARY_PATH} .= ":/usr/local/lib/python3.11/site-packages/torch/lib:/usr/local/lib/python3.11/site-packages/nvidia/cudnn/lib";
@ENV{qw(PORT HOST)} = (
    $ENV{PORT}              // 8080,
    $ENV{HOST}              // '0.0.0.0',
);

if (fork() == 0) {
    # child runs ollama serve and pipes output to log_tee.pl
    # run ['/bin/sh', '-c', 'exec ollama serve'], '2>&1', '|', ['/assets/log_tee.pl', 'ollama', '/tmp/ollama.log'], '>', \*STDOUT
    #     or die "Failed to start ollama serve: $!";
    setsid() or die "failed to start new daemin ollama";
    if (fork() == 0) {
        run ['/bin/sh', '-c', 'exec ollama serve'], '2>&1', '|', ['/assets/log_tee.pl', 'ollama', '/tmp/ollama.log'], '>', \*STDOUT;
        exit;
    }

    exit;
}

sleep 1;
my ($mod_fam, $hash);
for (@{LoadFile('/assets/models.yaml')}){
    fork() == 0 and exec 'ollama', 'pull', "$mod_fam:" . (keys %{$hash})[0]
        while  ($mod_fam, $hash) = each %{$_};
}
open my $fh, '<', '/dev/urandom' 
    or die "Cannot open /dev/urandom: $!";
read $fh, my $rand_bytes, 12;
close $fh;

my $secret = encode_base64($rand_bytes);
my $cmd = "WEBUI_SECRET_KEY=$secret exec uvicorn open_webui.main:app --host $ENV{HOST} --port $ENV{PORT} --forwarded-allow-ips '*'";
if (fork() == 0) {
    setsid() or die "failed to start new owebui session";
    if (fork() == 0){
    run ['/bin/sh', '-c', $cmd], '2>&1', '|', ['/assets/log_tee.pl', 'owebui', '/tmp/webui.log'], '>', \*STDOUT; # should be parent of ollama
    }
}
