package EC::Plugin::ContentProcessorCore;

use strict;
use warnings;
use JSON;

sub new {
    my ($class, %params) = @_;

    my $self = {%params};

    return bless $self, $class;
}

sub define_processors {
    my ($self) = @_;

    die 'Not implemented';
}

sub define_processor {
    my ($self, $step_name, $processor_type, $processor) = @_;
    $self->{processors}->{$step_name}->{$processor_type} = $processor;
}

sub run_serialize_body {
    my ($self, $step_name, $body) = @_;

    my $processor = $self->{processors}->{$step_name}->{'serialize_body'};
    if ($processor) {
        $processor->($self, $body);
    }
    else {
        $self->serialize_body($body);
    }
}

sub run_parse_response {
    my ($self, $step_name, $response) = @_;

    my $processor = $self->{processors}->{$step_name}->{'parse_response'};
    if ($processor) {
        $processor->($self, $response, $step_name);
    }
    else {
        $self->parse_response($response);
    }
}

sub serialize_body {
    my ($self, $body) = @_;

    return unless $body;

    my $json = encode_json($body);
    return $json;
}


sub parse_response {
    my ($self, $response) = @_;

    my $content_type = $response->header('Content-Type') || '';
    if ($content_type =~ m/json/) {
        $self->plugin->logger->debug($response->content);

        if ($response->content) {
            return decode_json($response->content);
        }
        else {
            $self->plugin->logger->info("Empty response; nothing to parse");
            return;
        }
    }
}

sub plugin {
    my ($self) = @_;
    return $self->{plugin};
}

1;
