package EC::Plugin::ContentProcessor;

use strict;
use warnings;
use JSON;

use base qw(EC::Plugin::ContentProcessorCore);

package EC::Plugin::ContentProcessor;

use strict;
use warnings;
use JSON;
use Data::Dumper;

use base qw(EC::Plugin::ContentProcessorCore);


=head1 SYNOPSYS

Here one can define custom processors for request & response. E.g., request
is not a plain JSON object but a file, or response does not contain JSON.

By default we assume that request body should be in JSON format and
response returns JSON as well.


Two processors can be defined:
    serialize_body - which will be used to serialize request body
    parse_response - which will be used to parse the content of the response

Code may look like the following:

    use constant {
        RETRIEVE_ARTIFACT => 'retrieve artifact',
        DEPLOY_ARTIFACT => 'deploy artifact',
    };


    sub define_processors {
        my ($self) = @_;

        $self->define_processor(DEPLOY_ARTIFACT, 'serialize_body', \&deploy_artifact);
        $self->define_processor(RETRIEVE_ARTIFACT, 'parse_response', \&download_artifact);
    }

    sub deploy_artifact {
        my ($self, $body) = @_;

        my $path = $body->{filesystemArtifact};

        open my $fh, $path or die "Cannot open $path: $!";
        binmode $fh;

        my $data = '';
        my $buffer;
        while( my $bytes_read = read($fh, $buffer, 1024)) {
            $data .= $buffer;
        }

        close $fh;


        # Here we return file content instead of JSON object
        return $data;
    }

    sub download_artifact {
        my ($self, $response) = @_;

        my $directory = $self->plugin->parameters(RETRIEVE_ARTIFACT)->{destination};

        $self->plugin->logger->debug("Destintion is $directory");
        my $filename = $response->header('x-artifactory-filename');


        my $dest_filename = $directory ? "$directory/$filename" : $filename;

        # And here we write a file instead of parsing response body as JSON

        open my $fh, ">$dest_filename" or die "Cannot open $dest_filename: $!";
        print $fh $response->content;
        close $fh;

        $self->plugin->logger->info("Artifact $dest_filename is saved");
        $self->plugin->set_summary("Artifact $dest_filename is saved");
    }


=cut



# autogen code ends here

sub define_processors {
    my ($self) = @_;

    $self->define_processor('create work items', 'serialize_body', \&create_workitem);
    $self->define_processor('update a work item', 'serialize_body', \&update_workitem);
    $self->define_processor('trigger a build', 'serialize_body', \&queue_build);
    $self->define_processor('upload a work item attachment', 'serialize_body', \&upload_attachment);
    # $self->define_processor('download an artifact from a git repository', 'parse_response', \&download_artifact);
}

# sub download_artifact {
#     my ($self, $response) = @_;

#     my $parameters = $self->plugin->parameters;
#     if ($parameters->{Accept} =~ /application\/octet-stream|application\/zip/) {

#         $self->plugin->logger->trace($response);
#         my $content_disposition = $response->header('content-disposition');
#         $content_disposition =~ m/attachment; filename=(.+)$/;
#         my $filename = $1;

#         my $destination = $parameters->{destination};
#         my $full_filename;
#         if ($destination) {
#             $full_filename = File::Spec->catfile($destination, $filename);
#         }
#         else {
#             $full_filename = $filename;
#         }

#         return { filename => $filename, fullPath => $full_filename };
#     }
#     else {
#         $self->SUPER::parse_response($response);
#     }
# }

sub upload_attachment {
    my ($self, $body) = @_;

    if ($self->plugin->parameters->{uploadType} eq 'chunked') {
        $self->plugin->logger->debug("Chunked upload, no content is required for the first request");
        return '';
    }

    if ($body->{filePath}) {
        open my $fh, $body->{filePath} or die "Cannot open file $body->{filePath}: $!";
        my $buf;
        return sub {
            my $bytes_read = read ($fh, $buf, 1024);
            $self->plugin->logger->debug("Reading file");
            if ($bytes_read) {
                return $buf;
            }
            else {
                return;
            }
        };
    }
    elsif ($body->{fileContent}) {
        return $body->{fileContent};
    }
}


sub queue_build {
    my ($self, $body) = @_;

    $self->plugin->logger->trace($body);

    my $refined = {};
    for my $key (keys %$body) {
        if ($key =~ m/\./) {
            my ($first, $second) = split(/\./, $key);
            $self->plugin->logger->trace($first, $second, $key);
            $refined->{$first}->{$second} = $body->{$key};
        }
        else {
            $refined->{$key} = $body->{$key};
        }
    }
    my $new_body = encode_json $refined;
    $self->plugin->logger->debug('New body', $new_body);
    return $new_body;
}


sub create_workitem {
    my ($self, $body) = @_;
    $self->_create_update_workitem($body);
}


sub update_workitem {
    my ($self, $body) = @_;
    $self->_create_update_workitem($body);
}

sub _create_update_workitem {
    my ($self, $body) = @_;

    my @list = ();
    my %mapping = (
        title => 'System.Title',
        description => 'System.Description',
        assignTo => 'System.AssignedTo',
        priority => 'Microsoft.VSTS.Common.Priority',
    );

    my $parameters = $self->plugin->parameters;
    if ($parameters->{additionalFields}) {
        my $o;
        eval {
            $o = decode_json($parameters->{additionalFields});
            1;
        } or do {
            return $self->plugin->bail_out("Additional fields should contain a valid JSON map: $@");
        };
        unless(ref $o eq 'HASH') {
            return $self->plugin->bail_out('Additional fields should contain a valid JSON map');
        }
        for my $key (keys %$o) {
            push @list, {op => 'add', path => "/fields/$key", value => $o->{$key}};
        }
    }

    if ($parameters->{requestBody}) {
        my $request_body;
        eval {
            $request_body = decode_json($parameters->{requestBody});
            1;
        } or do {
            return $self->plugin->bail_out('Request body should contain a valid JSON');
        };
        unless(ref $request_body eq 'ARRAY') {
            return $self->plugin->bail_out('Request body should contain JSON array');
        }
        push @list, @$request_body;
    }

    for my $key (keys %mapping) {
        if ($body->{$key}) {
            push @list, {op => 'add', path => "/fields/$mapping{$key}", value => $body->{$key}};
        }
    }
    my $new_body = encode_json(\@list);
    $self->plugin->logger->debug('New body', $new_body);
    return $new_body;
}

1;
