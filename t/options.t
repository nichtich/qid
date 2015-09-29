use v5.14;
use Test::More;
use Test::Output;
use App::qid;

my $exit;
sub qid {
    $exit = App::qid->run(\@_) 
}

output_like { qid } qr/^qid \[OPTIONS\]/, qr/^$/, 'usage by default';
is $exit, 0;

output_like { qid '--version' } qr/^qid \d+\.\d+\.\d+/, qr/^$/, 'version';
is $exit, 0;

output_like { qid '--foo' } qr/^$/, qr/^Unknown option: foo/, 'unknown option';
is $exit, 1;

done_testing;
