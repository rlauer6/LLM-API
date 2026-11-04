#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use LLM::API;

# Opt-in: never contact AWS during an ordinary test run.
if ( !$ENV{LLM_LIVE_BEDROCK_PDF} ) {
  plan skip_all => q{Set LLM_LIVE_BEDROCK_PDF=1 for the AWS integration test};
}

my $filename = $ENV{LLM_LIVE_PDF_FILE};
if ( !defined $filename || !-f $filename ) {
  BAIL_OUT(q{Set LLM_LIVE_PDF_FILE to an existing PDF file});
}

open my $fh, q{<:raw}, $filename
  or BAIL_OUT(sprintf q{Cannot open PDF %s: %s}, $filename, $!);
local $/;
my $pdf = <$fh>;
close $fh;

if ( $pdf !~ m{\A%PDF-} ) {
  BAIL_OUT(q{PDF input does not start with %PDF-});
}

my $model = $ENV{LLM_LIVE_BEDROCK_MODEL} // q{us.anthropic.claude-haiku-4-5-20251001-v1:0};
my $region = $ENV{AWS_REGION} // $ENV{AWS_DEFAULT_REGION} // q{us-east-1};

my $llm = LLM::API->new(
  provider   => q{bedrock},
  model      => $model,
  region     => $region,
  max_tokens => 256,
);

my $document = $llm->document(
  media_type => q{pdf},
  data       => \$pdf,
  title      => q{Integration Test PDF},
);

my $blocks = [
  $document,
  $llm->text(q{Read this PDF and give one brief sentence describing its contents.}),
];

subtest q{live Bedrock Converse with PDF} => sub {
  my $response = eval { $llm->send_prompt($blocks) };
  if ( $@ ) {
    fail(q{Converse request completed});
    diag($@);
    return;
  }

  if ( !$response->is_success ) {
    fail(q{Converse returned success});
    diag($response->error // q{No error detail available});
    return;
  }

  pass(q{Converse returned success});
  my $answer = $response->content->text;
  ok( defined $answer && length $answer, q{Received nonempty model answer} );
  diag(sprintf q{Model: %s}, $model);
  diag(sprintf q{Answer: %s}, $answer // q{});
  diag(sprintf q{Input tokens: %s}, $response->usage->input_tokens // q{unknown});
  diag(sprintf q{Output tokens: %s}, $response->usage->output_tokens // q{unknown});
};

done_testing();
1;
