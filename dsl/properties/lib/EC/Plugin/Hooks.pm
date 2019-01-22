package EC::Plugin::Hooks;

use strict;
use warnings;
use MIME::Base64 qw(encode_base64);
use JSON;
use Data::Dumper;

use base qw(EC::Plugin::HooksCore);
use File::Spec;
use EC::AzureDevOps::WorkItems;
use File::Path qw(mkpath);


=head1 SYNOPSYS

User-defined hooks

Available hooks types:

    before
    parameters
    request
    response
    parsed
    after

    ua - will be called when User Agent is created


    sub define_hooks {
        my ($self) = @_;

        $self->define_hook('my step', 'before', sub { ( my ($self) = @_; print "I'm before step my step" });
    }


=head1 SAMPLE


    sub define_hooks {
        my ($self) = @_;

        # step name is 'deploy artifact'
        # hook name is 'request'
        # This hook accepts HTTP::Request object
        $self->define_hook('deploy artifact', 'request', \&deploy_artifact);
    }

    sub deploy_artifact {
        my ($self, $request) = @_;

        # $self is a EC::Plugin::Hooks object. It has method ->plugin, which returns the EC::RESTPlugin object
        my $artifact_path = $self->plugin->parameters($self->plugin->current_step_name)->{filesystemArtifact};

        open my $fh, $artifact_path or die $!;
        binmode $fh;
        my $buffer;
        $self->plugin->logger->info("Writing artifact $artifact_path to the server");

        $request->content(sub {
            my $bytes_read = read($fh, $buffer, 1024);
            if ($bytes_read) {
                return $buffer;
            }
            else {
                return undef;
            }
        });
    }


=cut

# autogen end

sub define_hooks {
    my ($self) = @_;

    # $self->define_hook('create work items', 'parsed', \&create_work_item_response_parsed);
    # $self->define_hook('update a work item', 'parsed', \&update_work_item_response_parsed);
    # $self->define_hook('create work items', 'parameters', \&create_work_item_parameters);
    $self->define_hook('get default values', 'parameters', \&get_default_values);
    # $self->define_hook('get a work item', 'parsed', \&get_work_item_response_parsed);
    # $self->define_hook('delete work items', 'parsed', \&delete_work_item_response_parsed, {run_before_shared => 1});
    # $self->define_hook('delete work items', 'response', \&delete_work_item_response, {run_before_shared => 1});
    $self->define_hook('get work items', 'parsed', \&get_work_items_response_parsed);
    $self->define_hook('query work items', 'parsed', \&query_work_items_parsed);
    $self->define_hook('trigger a build', 'parsed', \&queue_build_parsed);
    $self->define_hook('trigger a build', 'parameters', \&queue_build_parameters);
    $self->define_hook('trigger a build', 'parsed', \&queue_build_parsed);
    $self->define_hook('trigger a build', 'after', \&queue_build_after);
    $self->define_hook('get a build', 'request', \&poll_build_status);
    $self->define_hook('get a build', 'parameters', \&get_build_id);
    $self->define_hook('get a build', 'after', \&get_build_after);
    # $self->define_hook('download an artifact from a git repository', 'content_callback', \&download_artifact_content_callback);
    $self->define_hook('upload a work item attachment', 'parsed', \&upload_attachment_parsed);
    $self->define_hook('upload a work item attachment', 'request', \&upload_attachment_request);
    $self->define_hook('upload a work item attachment', 'response', \&upload_attachment_response);
    $self->define_hook('upload a work item attachment', 'after', \&add_attachment_link);
    $self->define_hook('*', 'response', \&parse_json_error);
    $self->define_hook('*', 'request', \&general_request);

}

sub add_attachment_link {
    my ( $self, $parsed ) = @_;

    my $params = $self->plugin->parameters;
    my $config = $self->plugin->get_config_values($params->{config});

    for my $required (qw/workItemId/){
        $self->plugin->bail_out("Parameter '$required' is mandatory") unless $params->{$required};
    }

    #PATCH
    my $endpoint = $config->{endpoint} . "/$config->{collection}/_apis/wit/workitems/$params->{workItemId}";

    my $payload = [ {
        op    => "add",
        path  => "/relations/-",
        value => {
            rel => "AttachedFile",
            url => $parsed->{url},
            %{$params->{comment} ? { attributes => { comment => $params->{comment} } } : {}}
        }
    }];

    my $encoded_payload = encode_json($payload);

    my HTTP::Request $request = $self->plugin->get_new_http_request('PATCH' => $endpoint);
    $request->headers->header('Content-Type', 'application/json-patch+json');
    $request->content($encoded_payload);

    # Apply api version
    $self->general_request($request);

    my LWP::UserAgent $ua = $self->plugin->new_lwp();
    my HTTP::Response $response = $ua->request($request);

    if ($response->is_success){
      $self->plugin->success("Successfully linked the attachment");
    }
    else {
        $self->plugin->error($response->status_line());
    }
}

sub get_build_link {
    my ($self, $project_name, $build_id) = @_;

    my $endpoint = $self->get_endpoint_url;
    my @segments = $endpoint->path_segments;
    push @segments, $project_name, '_build', 'index';
    $endpoint->path_segments(@segments);
    $endpoint->query_form(_a => 'summary', buildId => $build_id);
    return $endpoint;
}

sub queue_build_parsed {
    my ($self, $parsed) = @_;

    my $params = $self->plugin->parameters;
    my $wait_for_build = $params->{waitForBuild};


    my $build_id = $parsed->{id};
    my $build_number = $parsed->{buildNumber};

    my $endpoint = $self->get_build_link($params->{project}, $build_id);

    my $summary = "Build $build_number, URL $endpoint";
    my $pipeline_summary = qq{<a href="$endpoint" target="_blank">$build_number</a>};
    my $pipeline_summary_key = qq{Build #$build_id Link};

    $self->plugin->set_summary($summary);
    $self->plugin->set_pipeline_summary($pipeline_summary_key, qq{<html>$pipeline_summary</html>});

    return unless $wait_for_build;

    my $timeout = $params->{waitTimeout};
    $self->poll_build($build_id, $timeout);
}


sub poll_build {
    my ($self, $build_id, $timeout) = @_;

    my $request = $self->create_request('GET',
        '#{{endpoint}}/#{{collection}}/#{project}/_apis/build/builds/' . $build_id . '?api-version=2.0',
        {}, '');
    my $ua = $self->plugin->new_lwp();
    my $time = 0;

    my $result;
    my $status;
    my $time_to_sleep = 30;

    while(!$result) {
        if ($time > $timeout) {
            $self->plugin->bail_out("Build status polling has timed out, status: $status");
        }
        my $info = $self->get_build_info($build_id);

        my $endpoint = $self->get_build_link($info->{project}->{name}, $build_id);
        my $build_number = $info->{buildNumber};
        my $summary = "Build $build_number, URL $endpoint";
        my $pipeline_summary = qq{<a href="$endpoint" target="_blank">$build_number</a>};
        my $pipeline_summary_key = qq{Build #$build_id Link};

        $result = $info->{result};
        my $status = $info->{status};
        $self->plugin->set_summary(qq{$summary, status: $status});
        $self->plugin->set_pipeline_summary($pipeline_summary_key, qq{<html>$pipeline_summary, status: $status</html>});

        unless ($result) {
            $self->plugin->logger->info("Status: $status, sleeping for $time_to_sleep seconds");
            sleep($time_to_sleep);
            $time += $time_to_sleep;
        }
        else {
            $self->plugin->logger->info("Polling finished, status is $status, result is $result");
        }
    }

}

sub ua {
    my ($self) = @_;

    unless($self->{ua}) {
        $self->{ua} = $self->plugin->new_lwp();
    }
    return $self->{ua};
}

sub get_build_info {
    my ($self, $build_id) = @_;

    my $request = $self->create_request('GET',
        '#{{endpoint}}/#{{collection}}/#{project}/_apis/build/builds/' . $build_id . '?api-version=2.0',
        {}, '');
    my $response = $self->ua->request($request);
    $self->parse_json_error($response);
    unless($response->is_success) {
        $self->plugin->bail_out("Cannot poll a build: " . $response->status_line);
    }
    my $json = decode_json($response->content);
    return $json;
}


sub queue_build_after {
    my ($self, $parsed) = @_;

    my $parameters = $self->plugin->parameters;
    $self->plugin->logger->trace($parsed);

    return unless $parameters->{mimicProcedureStatus};

    unless($parameters->{waitForBuild}) {
        $self->plugin->logger->info("Wait for build is not set, will not mimic build status");
        return;
    }
    $self->mimic_build_status($parameters->{project}, $parsed->{id});
}


sub mimic_build_status {
    my ($self, $project_name, $build_id) = @_;

    my $info = $self->get_build_info($build_id);
    my $status = $info->{status};
    my $result = $info->{result};

    if ($result =~ /^succeeded$/i ) {
        $self->plugin->set_summary(qq{Build $info->{buildNumber} succeeded, link } .
            $self->get_build_link($project_name, $build_id));
    }
    elsif ($result =~ /failed/i ) {
        $self->plugin->bail_out(qq{Build $info->{buildNumber} failed, link } .
            $self->get_build_link($project_name, $build_id));

    }
    else {
        $self->plugin->warning(qq{Build $info->{buildNumber}, status $status, result $result, link } .
            $self->get_build_link($project_name, $build_id));
    }

}

sub queue_build_parameters {
    my ($self, $parameters) = @_;

    my $definition = $parameters->{'definition.id'};
    my $queue = $parameters->{'queue.id'};

    unless($definition =~ /^\d+$/) {
        my $definition_id = $self->get_definition_id($definition);
        $parameters->{'definition.id'} = $definition_id;
    }
    if ($queue && $queue !~ /^\d+$/) {
        my $queue_id = $self->get_queue_id($queue);
        $parameters->{'queue.id'} = $queue_id if $queue_id;
    }
}

sub get_queue_id {
    my ($self, $queue) = @_;

    return unless $queue;

    my $request = $self->create_request('GET',
        '#{{endpoint}}/#{{collection}}/#{project}/_apis/distributedtask/queues?api-version=3.0-preview.1',
        {queueName => $queue}, '');
    $self->plugin->logger->trace($request);
    my $ua = $self->plugin->new_lwp();
    my $response = $ua->request($request);
    $self->plugin->logger->trace($response);
    $self->parse_json_error($response);

    unless($response->is_success) {
        $self->plugin->bail_out("Cannot get queue id for $queue: " . $response->status_line);
    }

    my $json = decode_json($response->content);
    if ($json->{count} == 1) {
        my $id = $json->{value}->[0]->{id};
        $self->plugin->logger->info(qq{Queue ID for queue "$queue" is $id});
        return $id;
    }
    elsif ($json->{count} == 0) {
        $self->plugin->bail_out(qq{No queues found by name "$queue"});
    }
    else {
        $self->plugin->logger->info('Queues', $json->{value});
        $self->plugin->bail_out(qq{More than one queue found by name "$queue"});
    }
}

sub get_definition_id {
    my ($self, $definition) = @_;

    unless($definition) {
        $self->plugin->bail_out('Definition id or name is required');
    }

    my $request = $self->create_request('GET', '#{{endpoint}}/#{{collection}}/#{project}/_apis/build/definitions?api-version=2.0',
        {name => $definition}, '');
    my $ua = $self->plugin->new_lwp();
    $self->plugin->logger->debug("Get definition id request URI: " . $request->uri);
    $self->plugin->logger->trace($request);

    my $response = $ua->request($request);
    $self->parse_json_error($response);

    unless($response->is_success) {
        $self->bail_out("Cannot get definition id for $definition: " . $response->status_line);
    }

    my $json = decode_json($response->content);
    $self->plugin->logger->debug('Definition response: ', $json);

    my $id;
    if ($json->{count} == 1) {
        my $def = $json->{value}->[0];
        $id = $def->{id};
        $self->plugin->logger->info(qq{Definition ID for name "$definition" is $id});
    }
    elsif($json->{count} == 0) {
        $self->plugin->bail_out(qq{No definitions found by name "$definition"});
    }
    else {
        $self->plugin->logger->info('Definitions', $json->{value});
        $self->plugin->bail_out(qq{More than one definition found by name "$definition"});
    }
    return $id;
}

sub get_build_id {
    my ($self, $parameters) = @_;

    my $build_id = $parameters->{buildId};
    my $request = $self->create_request('GET',
        '#{{endpoint}}/#{{collection}}/#{project}/_apis/build/builds?api-version=2.0',
        {buildNumber => $build_id}, '');

    my $ua = $self->plugin->new_lwp();
    $self->plugin->logger->debug("Get build id request URI: " . $request->uri);
    $self->plugin->logger->trace($request);
    my $response = $ua->request($request);
    $self->parse_json_error($response);

    unless($response->is_success) {
        $self->bail_out("Cannot get build ID: " . $response->status_line);
    }

    my $json = decode_json($response->content);
    $self->plugin->logger->debug("Build number request response", $json);
    my $id;

    if($json->{count} > 0) {
        my $first = $json->{value}->[0];
        $id = $first->{id};
    }
    else {
        $self->plugin->bail_out("Build $build_id is not found");
    }

    if ($id ne $build_id) {
        $self->plugin->logger->info("Build ID is $id");
    }
    $parameters->{buildId} = $id;
}

sub poll_build_status {
    my ($self, $request) = @_;

    my $params = $self->plugin->parameters;
    return unless $params->{waitForBuild};

    my $status;
    my $agent = $self->plugin->new_lwp();
    my $timeout = $params->{waitTimeout} || 60;
    my $wait_time = 0;
    my $time_to_sleep = 30;
    while(!$status || $status =~ /inprogress|notStarted/i) {
        my $response = $agent->request($request);
        if ($response->is_success) {
            my $json = decode_json($response->content);
            $status = $json->{status};
            unless($status =~ /inprogress|notStarted/) {
                return;
            }

            $self->plugin->logger->info("Build $json->{id} ($json->{buildNumber} is still in progress ($status)");
        }
        else {
            # Will exit with error if the request has failed
            $self->parse_json_error($response);
        }
        $wait_time += $time_to_sleep;
        if ($wait_time >= $timeout) {
            $self->plugin->bail_out("Wait operation has timed out, last status: $status");
        }
        sleep($time_to_sleep);
    }
}


sub get_build_after {
    my ($self, $parsed) = @_;

    my $status = $parsed->{result};
    my $build_number = $parsed->{buildNumber};


    if ($self->plugin->parameters->{mimicProcedureStatus}) {
        $self->mimic_build_status($parsed->{project}->{name}, $parsed->{id});
    }
    else {
        $self->plugin->set_summary("Status: $status");
    }
}

sub general_request {
    my ($self, $request) = @_;

    $self->plugin->logger->debug($request);
    my $uri = $request->uri;

    my $params = $self->plugin->parameters;
    my $config = $self->plugin->get_config_values($params->{config});

    require EC::AzureDevOps::Plugin;
    my $api_version = EC::AzureDevOps::Plugin::get_api_version($request->uri, $config);

    my %query_form = $uri->query_form;
    $query_form{'api-version'} = $api_version;
    $uri->query_form(%query_form);

    $request->uri($uri);
}


sub download_artifact_content_callback {
    my ($self) = @_;

    my $params = $self->plugin->parameters;
    if ($params->{Accept} eq 'application/json') {
        # Metadata, no need to download files
        return;
    }

    my $destination = $params->{destination};
    if($destination && !-e $destination) {
        my @created = mkpath($destination);
        unless(@created) {
            die "Cannot create path $destination: $!";
        }
    }

    my $sub = sub {
        my ($chunk, $res) = @_;
        eval {
            my $saved = $self->{download_git_artifact_data};
            $self->plugin->logger->trace($saved);
            my $fh = $saved->{fh};

            unless($fh) {
                my $content_disposition = $res->header('content-disposition');
                my $filename;
                if ($content_disposition) {
                    $content_disposition =~ m/attachment; filename=(.+)$/;
                    $filename = $1;
                }
                else {
                    my $path = $params->{scopePath};
                    my @parts = split(/\//, $path);
                    $filename = $parts[-1];
                }
                $self->plugin->logger->trace($res);

                my $full_filename;

                if ($params->{destination}) {
                    $full_filename = File::Spec->catfile($params->{destination}, $filename);
                }
                else {
                    $full_filename = $filename;
                }
                open $fh, '>', $full_filename or die "Cannot open $full_filename: $!";
                $saved = {filename => $filename, fullPath => $full_filename, fh => $fh};
                $self->{download_git_artifact_data} = $saved;
            }
            $self->plugin->logger->debug('Downloading ' . length($chunk) . ' bytes into ' . $saved->{fullPath});
            print $fh $chunk;
            1;
        } or do {
            $self->plugin->bail_out("Error occured: $@");
        };
    };

    $_[1] = $sub;
}

sub upload_attachment_request {
    my ($self, $request) = @_;

    if ($self->plugin->parameters->{uploadType} eq 'chunked') {
        $request->header('Content-Length' => 0);
    }
}


sub upload_attachment_response {
    my ($self, $response) = @_;

    return unless $self->plugin->parameters->{uploadType} eq 'chunked';
    $self->plugin->logger->trace($response);

    return unless $response->is_success;

    my $data = decode_json($response->content);

    my $file_path = $self->plugin->parameters->{filePath};
    unless (-f $file_path) {
        $self->plugin->bail_out("No file found: $file_path");
    }

    open my $fh, $file_path or $self->plugin->bail_out("Cannot open $file_path: $!");
    my $cl_start = 0;

    my $buf;
    my $total = -s $file_path;
    $self->plugin->logger->debug("Total size: $total");

    $self->plugin->logger->debug($response->request);
    my $auth = $response->request->header('Authorization');
    my %request_query_form = URI->new($response->request->url)->query_form;

    $self->plugin->logger->debug("Auth: $auth");
    my $ua = $self->plugin->new_lwp();

    my $url = URI->new($data->{url});
    $url->query_form($url->query_form, uploadType => 'chunked', 'api-version' => $request_query_form{'api-version'});
    $self->plugin->logger->debug($url);

    my $cl_end = 0;
    my $total_mb = $total / (1024 * 1024);

    while( my $bytes_read = read ($fh, $buf, 1024 * 10 * 1024) ) {
        $cl_end = $bytes_read - 1 + $cl_start;
        my $content_length = "$cl_start-$cl_end";

        my $request = $self->plugin->get_new_http_request(PUT => $url);
        $request->header('Authorization' => $auth);
        $request->header('Content-Range' => "bytes $content_length/$total");
        $request->header('Content-Type' => 'application/octet-stream');
        $request->content($buf);

        $response = $ua->request($request);
        unless($response->is_success) {
            $self->plugin->logger->trace($response);
            $self->plugin->bail_out($response->content);
        }
        $cl_start += $bytes_read;
        my $uploaded_mb = $cl_start /(1024 * 1024);
        $self->plugin->set_summary(sprintf "Upload progress: %.2f/%.2f Mb", $uploaded_mb, $total_mb);
    }
    $self->plugin->logger->debug('Finished');
}

sub upload_attachment_parsed {
    my ($self, $parsed) = @_;

    $self->plugin->logger->debug($parsed);

    my $url = $parsed->{url};
    $url = URI->new($url);
    $url->query_form($url->query_form, 'api-version' => '1.0');
    $self->plugin->set_summary("Attachment: $url");
    $self->plugin->set_pipeline_summary(qq{Work item attachment URL}, qq{<html><a href="$url" target="_blank">$url</a></html>});
}


sub parse_json_error {
    my ($self, $response) = @_;

    return if $response->is_success;

    my $json;
    eval {
        $json = decode_json($response->content);
        1;
    } or do {
        return;
    };

    my $formatted_response = JSON->new->utf8->pretty->encode($json);
    $self->plugin->logger->info('Got error', $formatted_response);
    my $message = $json->{message};
    if ($message) {
        $self->plugin->bail_out($message);
    }
}

sub get_default_values {
    my ($self, $parameters) = @_;

    my $type = $parameters->{workItemTypeName};
    if ($type !~ m/^\$/) {
        $type = '$' . $type;
    }
    $parameters->{workItemTypeName} = $type;
}

# sub create_work_item_parameters {
#     my ($self, $parameters) = @_;
#
#     my $type = $parameters->{type};
#     $type = '$' . $type unless $type =~ m/^\$/;
#     $parameters->{type} = $type;
# }
#
# sub create_work_item_response_parsed {
#     my ($self, $response) = @_;
#
#     my $id = $response->{id};
#     my $url = $self->create_item_url($response->{fields}->{'System.TeamProject'}, $id);
#
#     $self->plugin->logger->info("A new work item has been created with id: $id");
#     $self->plugin->logger->info("URL: $url");
#     $self->plugin->set_summary("New work item URL: $url");
#     my $pipeline_summary = qq{<html><a href="$url" target="_blank">$url</a></html>};
#     $self->plugin->set_pipeline_summary("Work item URL", $pipeline_summary);
# }
#
# sub update_work_item_response_parsed {
#     my ($self, $response) = @_;
#
#     my $id = $response->{id};
#     my $url = $self->create_item_url($response->{fields}->{'System.TeamProject'}, $id);
#
#     $self->plugin->logger->info("URL: $url");
#     $self->plugin->set_summary("Updated work item URL: $url");
#     my $pipeline_summary = qq{<html><a href="$url" target="_blank">$url</a></html>};
#     $self->plugin->set_pipeline_summary("Updated work item URL", $pipeline_summary);
# }


sub get_work_item_response_parsed {
    my ($self, $response) = @_;

    my $id = $response->{id};
    my $url = $self->create_item_url($response->{fields}->{'System.TeamProject'}, $id);

    my $title = $response->{fields}->{'System.Title'} || '-- no title';
    my $type = $response->{fields}->{'System.WorkItemType'} || '-- no type';
    my $assigned = $response->{fields}->{'System.AssignedTo'} || 'No one';

    my $summary = qq{
ID: $id
URL: $url
Title: $title
Type: $type
Assigned to: $assigned
};
    $self->plugin->logger->info($summary);

    my $pipeline_summary = qq{<html><a href="$url" target="_blank">$title</a></html> };
    $self->plugin->set_pipeline_summary("Work item #$id", $pipeline_summary);
    $self->plugin->set_summary($summary);
}

sub get_work_items_response_parsed {
    my ($self, $parsed) = @_;

    my $count = $parsed->{count};
    my @titles = ();
    my $more = 0;
    for my $item (@{$parsed->{value}}) {
        my $title = $item->{fields}->{'System.Title'};

        if ( scalar @titles > 5) {
            $more = 1;
            last;
        }
        else {
            push @titles, $title if $title;
        }
    }
    my $summary = "Got work items: $count, titles: " . join(", ", @titles);
    $summary .= ', ' . ($count - 5) . ' items more'  if $more;
    $self->plugin->set_pipeline_summary("Work items retrieved", $summary);
    $self->plugin->set_summary($summary);
}

sub delete_work_item_response {
    my ($self, $response) = @_;

    my $strict_mode = $self->plugin->parameters->{strictMode};

    if ($response->code == 404 && !$strict_mode) {
        $self->plugin->logger->info("The item does not exist");
        $self->plugin->logger->info("Finishing procedure");
        $self->plugin->warning('The item does not exist');
        exit 0;
    }
}

sub delete_work_item_response_parsed {
    my ($self, $response) = @_;

    my $id = $response->{id};
    my $deleted_by = $response->{deletedBy} || 'No one';
    my $url = $response->{url};

    my $summary = qq{
ID: $id
URL: $url
Deleted by: $deleted_by
};
    $self->plugin->logger->info($summary);
    my $pipeline_summary = qq{<html><a href="$url" target="_blank">$url</a>; deleted by: $deleted_by</html>};
    $self->plugin->set_pipeline_summary("Deleted work item #$id", $pipeline_summary);
    $self->plugin->set_summary($summary);
}

sub create_item_url {
    my ($self, $project, $id) = @_;

    my $config_name = $self->plugin->parameters->{config};
    my $config = $self->plugin->get_config_values($config_name);

    my $endpoint = $config->{endpoint};
    my $collection = $config->{collection};

    my $url = "$endpoint/$collection/$project/_workitems?id=$id&_a=edit";
    return $url;
}


sub get_endpoint_url {
    my ($self) = @_;

    my $config_name = $self->plugin->parameters->{config};
    my $config = $self->plugin->get_config_values($config_name);

    my $endpoint = $config->{endpoint};
    my $collection = $config->{collection};


    return URI->new(join('/', $endpoint, $collection));
}


sub create_request {
    my ($self, $method, $url, $query, $body) = @_;

    my $parameters = $self->plugin->parameters;
    my $config = $self->plugin->get_config_values($parameters->{config});

    my $key = qr/[\w\-.?!]+/;
    # replace placeholders
    my $config_values_replacer = sub {
        my ($value) = @_;
        return $config->{$value} || '';
    };
    $url =~ s/#\{\{($key)\}\}/$config_values_replacer->($1)/ge;

    my $parameters_replacer = sub {
        my ($value) = @_;
        return $parameters->{$value} || '';
    };

    $url =~ s/#\{($key)\}/$parameters_replacer->($1)/ge;

    my $uri = URI->new($url);
    my %query = $uri->query_form;
    my %headers = ();

    if ($query) {
        %query = (%query, %$query);
    }

    $uri->query_form(%query);
    $self->plugin->logger->debug("Endpoint: $uri");


    my $request = $self->plugin->get_new_http_request($method, $uri);

    my $username = $config->{userName};
    my $password = $config->{password};

    $request->content($body) if $body;
    $request->header('Content-Type' => 'application/json');
    return $request;
}



1;
