package EC::AzureDevOps::Plugin;
use strict;
use warnings FATAL => 'all';

use base 'EC::Plugin::Core';

use Data::Dumper;
use JSON::XS qw/decode_json encode_json/;
use Encode 'decode';

use EC::Plugin::Microrest;
use EC::AzureDevOps::WorkItems;

use constant {
    FORBIDDEN_FIELD_NAME_PREFIX => '_'
};
use constant FORBIDDEN_FIELD_NAME_PROPERTY_SHEET => qw(acl createTime lastModifiedBy modifyTime owner propertySheetId description);

my %MS_FIELDS_MAPPING = (
    title       => 'System.Title',
    description => 'System.Description',
    assignto    => 'System.AssignedTo',
    priority    => 'Microsoft.VSTS.Common.Priority',
    commentbody => 'System.History'
);


sub after_init_hook {
    my ( $self, %params ) = @_;

    $self->{plugin_name} = '@PLUGIN_NAME@';
    $self->{plugin_key} = '@PLUGIN_KEY@';
    my $debug_level = 0;
    my $proxy;

    $self->logger->info($self->{plugin_name});

    if ($self->{plugin_key}) {
        eval {
            $debug_level = $self->ec()->getProperty(
                "/plugins/$self->{plugin_key}/project/debugLevel"
            )->findvalue('//value')->string_value();
        };

        eval {
            $proxy = $self->ec->getProperty(
                "/plugins/$self->{plugin_key}/project/proxy"
            )->findvalue('//value')->string_value;
        };
    }

    if ($debug_level) {
        $self->debug_level($debug_level);
        $self->logger->level($debug_level);
        $self->logger->debug("Debug enabled for $self->{plugin_key}");
    }
    else {
        $self->debug_level(0);
    }

    if ($proxy) {
        $self->{proxy} = $proxy;
        $self->logger->info("Proxy enabled: $proxy");
    }

    eval {
        my $log_to_property = $self->ec->getProperty('/plugins/@PLUGIN_KEY@/project/ec_debug_logToProperty')->findvalue('//value')->string_value;
        $self->logger->log_to_property($log_to_property);
        $self->logger->info("Logs are redirected to property $log_to_property");
    };
}

sub step_create_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        project             => { label => 'Project Name', required => 1 },
        type                => { label => 'Type', required => 1 },
        title               => { label => 'Title', required => 1 },
        priority            => { label => 'Priority', check => 'number' },
        assignTo            => { label => 'Assign To' },
        description         => { label => 'Description' },
        additionalFields    => { label => 'Additional Fields', check => 'json', json => 'array' },
        workItemsJSON       => { label => 'Work Items JSON', check => 'json', json => 'array' },
        resultPropertySheet => { label => 'Result Property Sheet' },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(sort keys %procedure_parameters);

    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    # Api version should be sent in query
    my $api_version = get_api_version('/_apis/wit/workitems/', $config);

    # Reading values from the parameters
    my %generic_fields = $self->parse_generic_create_update_parameters($params);

    my @work_item_hashes = @{$self->build_create_multi_entity_payload($params, %generic_fields)};

    # Sending requests one by one
    my @created_items = ();
    for my $work_item (@work_item_hashes) {

        # Prepending '$' to the type name and removing from hash
        my $type = ( $work_item->{type} =~ /^\$/ ) ? $work_item->{type} : '$' . $work_item->{type};
        delete $work_item->{type};

        # Building API path (includes type)
        my $api_path = $params->{project} . '/_apis/wit/workitems/' . $type;
        $self->logger->debug("API Path: $api_path");

        # Forming request payload
        my @payload = map {_generate_field_op_hash($_, $work_item->{$_})} keys %$work_item;

        # Adding Additional fields
        if ($params->{additionalFields}) {
            push @payload, @{$self->parse_azure_additional_fields($params->{additionalFields})};
        }

        $self->logger->debug("PAYLOAD", \@payload);

        my $result = $client->post($api_path, { 'api-version' => $api_version }, \@payload);

        push @created_items, $result;
    }

    # Save to the properties
    $self->save_work_items(
        \@created_items,
        $params->{resultPropertySheet}, $params->{resultFormat},
        \&_transform_work_item
    );

    my $count = scalar(@created_items);
    my $summary = "Successfully created $count work item" . ( ( $count > 1 ) ? 's' : '' ) . '.';

    $self->set_pipeline_summary("Create work items", $summary);
    $self->set_summary($summary);
}

sub step_update_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemIds         => { label => 'Work Item ID(s)', required => 1, check => \&_number_array_check },
        title               => { label => 'Title' },
        priority            => { label => 'Priority', check => 'number' },
        assignTo            => { label => 'Assign To' },
        description         => { label => 'Description' },
        commentBody         => { label => 'Comment Body' },
        additionalFields    => { label => 'Additional Fields' },
        resultPropertySheet => { label => 'Result Property Sheet' },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(sort keys %procedure_parameters);

    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    # Api version should be sent in query
    my $api_version = get_api_version('/_apis/wit/workitems/', $config);

    # Generating the payload from the parameters
    my %generic_fields = $self->parse_generic_create_update_parameters($params);

    $self->logger->debug("Generic parameters", \%generic_fields);

    # Sending requests one by one
    my @updated_items = ();
    for my $id (split(',\s?', $params->{workItemIds})) {
        my $api_path = '/_apis/wit/workitems/' . $id;
        $self->logger->debug("API Path: $api_path");

        my @payload = map {_generate_field_op_hash($_, $generic_fields{$_})} keys %generic_fields;
        $self->logger->debug("Parameters-defined payload", \%generic_fields);

        # Adding Additional fields
        if ($params->{additionalFields}) {
            push @payload, @{$self->parse_azure_additional_fields($params->{additionalFields})};
        }

        $self->logger->debug("Full payload", \@payload);

        if (! @payload) {
            my $summary = "Nothing to update.";
            $self->set_pipeline_summary("Update result", $summary);
            $self->warning($summary);

            exit 0;
        }

        my $result = $client->patch($api_path, { 'api-version' => $api_version }, \@payload);
        push @updated_items, $result;
    }

    # Save the properties
    # Save to the properties
    $self->save_work_items(
        \@updated_items,
        $params->{resultPropertySheet}, $params->{resultFormat},
        \&_transform_work_item
    );

    my $count = scalar(@updated_items);
    my $summary = "Successfully updated $count work item" . ( ( $count > 1 ) ? 's' : '' ) . '.';

    $self->set_pipeline_summary("Update work items", $summary);
    $self->set_summary($summary);
}

sub step_delete_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemIds         => { label => 'Work Item Id(s)', required => 1, check => \&_number_array_check },
        resultPropertySheet => { label => 'Result Property Sheet' },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    my $api_version = get_api_version('/_apis/wit/workitems/', $config);

    my @deleted = ();
    my @unexisting = ();
    for my $id (split(',\s?', $params->{workItemIds})) {
        my $api_path = "_apis/wit/workitems/${id}";

        my $result;
        eval {
            $result = $client->delete($api_path, { 'api-version' => $api_version });
            push @deleted, $result;
            1;
        } or do {
            my ( $error ) = $@;

            # 404 Not found.
            if (! ref $error && $error =~ /Work item [0-9]+ does not exist/) {
                $self->logger->info("Work item $id does not exist.\n");
                push @unexisting, $id;
            }
            else {
                $self->bail_out("Can't remove Work Item $id, \n$@");
            }
        };

    }

    # Save the properties
    # Save to the properties
    $self->save_work_items(
        \@deleted,
        $params->{resultPropertySheet}, $params->{resultFormat},
        \&_transform_delete_result
    );

    my $count = scalar(@deleted);
    my $summary = '';

    if (@deleted) {
        $summary = "Successfully deleted $count work item" . ( ( $count > 1 ) ? 's' : '' ) . '.';
    }

    if (@unexisting) {
        $summary .= "\n" if (@deleted);

        $summary .= "Work item(s) " . ( join(@unexisting) ) . " was not found";
        $self->warning("Some work items were not found. See the job logs");
    }

    $self->set_pipeline_summary("Delete work items", $summary);
    $self->set_summary($summary);
}

sub step_get_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemIds         => { label => 'Work Item Id(s)', required => 1, check => \&_number_array_check },
        fields              => { label => 'Fields' },
        asOf                => { label => 'As of (date)', check => \&_date_time_check },
        expandRelations     => { label => 'Expand relationships' },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    # Get the work items
    my @work_item_ids = split(',\s?', $params->{workItemIds});
    my $result = $self->get_work_items(\@work_item_ids, $params);
    if (! $result || ! $result->{value} || ref $result->{value} ne 'ARRAY') {
        $self->bail_out("Received wrong result format", $result);
    }

    # API will return 'undef' for workItems that were not found
    my @clear_list = grep {defined $_} @{$result->{value}};

    # Save to the properties
    $self->save_work_items(
        \@clear_list,
        $params->{resultPropertySheet}, $params->{resultFormat},
        \&_transform_work_item
    );
    my @result_ids = map {$_->{id}} @clear_list;

    my $summary = '';
    # Checking for not existing workItems
    if (scalar @result_ids != scalar @work_item_ids) {
        my @not_found = ();
        my @sorted_result_ids = sort @result_ids;

        for my $id (sort @work_item_ids) {
            # If ID from user-given list is not present in the result
            if (! grep {$_ eq $id} @sorted_result_ids) {
                push @not_found, $id;
            }
        }
        $summary = "Work Item(s) with the following IDs were not found: " . join(', ', @not_found);
        $self->warning($summary);
    }
    else {
        $summary = "Work items are saved to a property sheet.";
        $self->success($summary);
    }

    $self->logger->info($summary);

    $self->set_pipeline_summary($summary);
    $self->set_summary($summary);

    exit 0;
}

sub step_query_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        project             => { label => 'Project' },
        queryId             => { label => 'Query ID' },
        queryText           => { label => 'Query Text' },
        timePrecision       => { label => 'Time precision' },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    # One of this should be present
    if (! ( $params->{queryId} || $params->{queryText} )) {
        $self->bail_out("Either '$params->{queryId}->{label}' or '$params->{queryText}->{label}' should be present");
    }

    # If queryText contains @project, "Project" should be specified
    if (! $params->{queryId} && $params->{queryText}
        && ! $params->{project} && $params->{queryText} =~ /\@project/
    ) {
        $self->bail_out("Your query contains reference to a project, but parameter 'Project' is not specified.")
    }

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config, 'application/json');
    my $api_version = get_api_version('/_apis/wit/wiql/', $config);

    my $result = undef;
    if ($params->{queryId}) {
        $result = $client->get(
            '_apis/wit/wiql/' . $params->{queryId},
            { 'api-version' => $api_version }
        );
    }
    else {
        $result = $client->post(
            '_apis/wit/wiql',
            { 'api-version' => $api_version },
            { query => $params->{queryText} }
        );
    }

    $self->logger->debug('Parsed response', $result);

    my $ids = [];
    if ($result->{queryType} eq 'flat') {
        $ids = EC::AzureDevOps::WorkItems::collect_flat_ids($result);
    }
    elsif ($result->{queryType} eq 'tree') {
        $ids = EC::AzureDevOps::WorkItems::collect_tree_ids($result);
    }
    elsif ($result->{queryType} eq 'oneHop') {
        $ids = EC::AzureDevOps::WorkItems::collect_one_hop_ids($result);
    }
    else {
        $self->bail_out("Unknown type of query: $result->{queryType}");
    }

    if (! scalar(@$ids)) {
        $self->warning("No work items was found for the query.");
        exit 0;
    }

    # Save IDS
    $self->logger->info("IDs of the found work items: " . join(', ', @$ids));

    # Get fields from the query
    my @fields_names = map {$_->{referenceName}} @{$result->{columns}};
    my $fields_string = join(',', @fields_names);

    $self->logger->info("Fields mentioned in the query:" . $fields_string);

    # Get Work Items for given ids
    my $work_items_result = $self->get_work_items($ids, {
        config => $params->{config},
        fields => $fields_string
    });
    $self->logger->debug("Work items result", $work_items_result);

    my $work_items_list = $work_items_result->{value};
    if (! $work_items_list) {
        $self->bail_out("Failed to receive work items. Check for errors above");
    }

    $self->save_work_items($work_items_list, $params->{resultPropertySheet}, $params->{resultFormat});

    my $count = $work_items_result->{count};
    my @titles = ();
    my $more = 0;
    for my $item (@{$work_items_result->{value}}) {
        my $title = $item->{fields}->{'System.Title'};
        if (scalar @titles > 5) {
            $more = 1;
            last;
        }
        else {
            push @titles, $title if $title;
        }
    }

    my $summary = "Got work items: $count, titles: " . join(", ", @titles);
    $summary .= ', ' . ( $count - 5 ) . ' items more' if $more;
    $self->set_pipeline_summary("Work items retrieved", $summary);
    $self->set_summary($summary);
}

sub step_get_default_values {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        project             => { label => 'Project', required => 1 },
        workItemType        => { label => 'Work Item Type', required => 1 },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config, 'application/json');
    my $api_version = get_api_version('/_apis/wit/workitems/', $config);

    my $type = ( $params->{workItemType} =~ /^\$/ ) ? $params->{workItemType} : '$' . $params->{workItemType};
    my $api_path = $params->{project} . '/_apis/wit/workitems/' . $type;

    my $responce = $client->get($api_path, {
        'api-version' => $api_version
    });

    $self->logger->debug("Responce", $responce);

    if (! $responce || ref $responce ne 'HASH' || ! $responce->{fields}) {
        $self->bail_out("Received wrong result. Please check errors above.");
    }

    $self->save_parsed_data($responce->{fields}, $params->{resultPropertySheet}, $params->{resultFormat});

    my $summary = "Default values were saved to a $params->{resultPropertySheet}";
    $self->set_pipeline_summary("Get Default Values", $summary);
    $self->set_summary($summary);
}

sub step_upload_work_item_attachment {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemId          => { label => 'Work Item ID', required => 1, check => 'number' },
        comment             => { label => 'Comment' },
        filename            => { label => 'Attachment Filename', required => 1 },
        uploadType          => { label => 'Upload Type', required => 1 },
        filePath            => { label => 'File Path', check => 'file', file => 'r' },
        fileContent         => { label => 'File Content' },
        resultPropertySheet => { label => 'Result Property Sheet' },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    if (! $params->{filePath} && ! $params->{fileContent}) {
        $self->bail_out("Either 'File Path' or a 'File Content' should be specified.");
    }
    if ($params->{filePath} && $params->{fileContent}) {
        $self->bail_out("Only 'File Path' or a 'File Content' should be specified.");
    }

    if ($params->{uploadType} eq 'chunked' && $params->{fileContent}) {
        $self->logger->info("[WARNING] Chunked upload mode is incompatible with a 'File Content'. Switching to a 'Simple' mode.");
        $params->{uploadType} = 'simple';
    }

    my $config = $self->get_config_values($params->{config});

    # Use upload the file depending on the upload type
    my $attachment_url;
    if ($params->{uploadType} eq 'chunked') {
        my %upload_params = (
            filename => $params->{filename}
        );

        $upload_params{filePath} = $params->{filePath} if ($params->{filePath});
        $attachment_url = $self->upload_chunked($config, %upload_params);
    }
    elsif ($params->{uploadType} eq 'simple') {
        my %upload_params = (
            filename => $params->{filename}
        );

        $upload_params{filePath} = $params->{filePath} if ($params->{filePath});
        $upload_params{fileContent} = $params->{fileContent} if ($params->{fileContent});

        $attachment_url = $self->upload_simple($config, %upload_params);
    }

    if (! $attachment_url) {
        $self->bail_out("Upload failed. Check log for errors.")
    }

    $self->logger->debug("Attachment URL: $attachment_url");

    # After successful request, update a work item with a link
    my $request_path = '_apis/wit/workitems/' . $params->{workItemId};
    my $api_version = get_api_version($request_path, $config);
    my EC::Plugin::MicroRest $client = $self->get_microrest_client($config);

    my $link_attachment_resp = $client->patch($request_path, { 'api-version' => $api_version },
        [ {
            op    => "add",
            path  => "/relations/-",
            value => {
                rel => "AttachedFile",
                url => $attachment_url,
                %{$params->{comment} ? { attributes => { comment => $params->{comment} } } : {}}
            }
        } ]
    );

    if (! $link_attachment_resp) {
        $self->bail_out("Attachment is uploaded, but linking it to the Work Item failed. Check for errors above.")
    }

    # Set summary
    $self->success("Attachment: $attachment_url");
    $self->set_pipeline_summary(
        "Work item attachment URL",
        qq{<html><a href="$attachment_url" target="_blank">$attachment_url</a></html>}
    );

}

sub step_trigger_build {
    my ( $self ) = @_;

    my %procedure_parameters = (
        'config'              => { label => 'Configuration', required => 1 },
        'project'             => { label => 'Project', required => 1 },
        'definitionId'        => { label => 'Definition ID or name', required => 1 },
        'queueId'             => { label => 'Queue ID or Name' },
        'sourceBranch'        => { label => 'Source branch' },
        'parameters'          => { label => 'Parameters', check => 'key_value' },
        'resultPropertySheet' => { label => 'Result Property Sheet', required => 1 },
        'resultFormat'        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);
    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config, 'application/json');

    # Check ad find IDs for given names
    if ($params->{definitionId} !~ /^\d+$/) {
        $self->logger->info("Looking for ID of the Build Definition with name '$params->{definitionId}'.");
        $params->{definitionId} = $self->find_definition_id_by_name($config, $params->{project}, $params->{definitionId});
    }
    if ($params->{queueId} && $params->{queueId} !~ /^\d+$/) {
        $self->logger->info("Looking for ID of the Queue with name '$params->{definitionId}'.");
        $params->{queueId} = $self->find_queue_id_by_name($config, $params->{project}, $params->{queueId});
    }

    my $request_path = $params->{project} . '/_apis/build/builds';
    my $api_version = get_api_version($request_path, $config);

    my %payload = ();
    $payload{Definition} = { Id => $params->{definitionId} };
    $payload{Queue} = { Id => $params->{queueId} } if ($params->{queueId});
    $payload{sourceBranch} = $params->{sourceBranch} if ($params->{sourceBranch});

    # Parse and add the parameters if necessary
    if ($params->{parameters}) {
        # Parse raw text to a key-pairs
        my $parameters = $self->parse_build_parameters($params->{parameters});
        $payload{parameters} = JSON::encode_json($parameters);
    }

    $self->logger->debug("Payload", \%payload);

    my $build = $client->post($request_path, { 'api-version' => $api_version }, \%payload);
    $self->logger->debug("Result", $build);

    $build = $self->_transform_build_result($build);

    $self->save_parsed_data($build, $params->{resultPropertySheet}, $params->{resultFormat});

    $self->success("Build values are saved to a specified property");
    $self->set_pipeline_summary(
        "Build URL",
        qq{<html><a href="$build->{url}" target="_blank">$build->{buildNumber}</a></html>}
    );
}

sub step_get_build {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        project             => { label => 'Project', required => 1 },
        buildId             => { label => 'Build Id or Number', required => 1 },
        buildDefinitionName => { label => 'Build Definition Name' },
        waitForBuild        => { label => 'Wait For Build' },
        waitTimeout         => { label => 'Wait Timeout', check => 'number' },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);
    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    # If buildId contains something not like a simple integer, assume this is a build number
    if ($params->{buildId} !~ /^\d+$/) {
        # Get a build id by name
        if (! $params->{buildDefinitionName}) {
            $self->bail_out("Parameter 'Build Definition Name' is required"
                . " if you've specified Build number in a 'Build Id of Number' parameter.");
        }

        my $definition_id = $self->find_definition_id_by_name($params->{buildDefinitionName});

        $self->logger->debug("Looking for Id of a build with name '$params->{buildId}'");
        $params->{buildId} = $self->find_build_id_by_number(
            $config,
            $params->{project},
            $definition_id,
            $params->{buildId}
        );
        $self->logger->info("Id of a build is '$params->{buildId}'");

        if (! $params->{buildId}) {
            $self->bail_out("Failed to get a build ID. Check for errors above.")
        }
    }

    my $request_path = '_apis/build/builds/' . $params->{buildId};
    my $api_version = get_api_version($request_path, $config);
    my $build = $client->get($request_path, { 'api-version' => $api_version });

    if (! $build) {
        $self->bail_out("Failed to receive a build. Check for errors above.");
    }

    # If have to wait and should wait, then wait
    if ($params->{waitForBuild} && $build->{status} !~ 'completed|postponed|cancelling') {
        $build = $self->wait_for_build($client, $config, $params->{buildId}, $params->{waitTimeout});
    }

    $build = $self->_transform_build_result($build);

    $self->save_parsed_data($build, $params->{resultPropertySheet}, $params->{resultFormat});

    $self->success("Build values are saved to a specified property");
    $self->set_pipeline_summary(
        "Build URL",
        qq{<html><a href="$build->{url}" target="_blank">$build->{buildNumber}</a></html>}
    );

}

sub step_collect_reporting_data {

}

sub find_build_id_by_number {
    my ( $self, $config, $project, $definitionId, $build_number ) = @_;
    return unless $build_number;

    # Make a list request
    my $request_path = $project . '/_apis/build/builds';
    my $api_version = get_api_version($request_path, $config);
    my $client = $self->get_microrest_client($config);

    my $search_result = $client->get($request_path, {
        'api-version' => $api_version,
        buildNumber   => $build_number,
        definitions   => $definitionId,
        queryOrder    => 'finishTimeDescending'
    });

    if (! $search_result || ref $search_result ne 'HASH') {
        $self->bail_out("Failed to find a build by number. API returned wrong value. Check errors above");
    }
    if (! $search_result->{count}) {
        $self->bail_out("Failed to find a build by number. No builds found for specified Build Number.");
    }

    # Check build
    if ($search_result->{count} > 1) {
        my $build_numbers_str = join(', ', map {"$_->{buildNumber}($_->{id})"} @{$search_result->{value}});
        $self->logger->info("Found more than one ($search_result->{count}) build for the given build number ($build_number). "
            . "Names are: $build_numbers_str. "
            . "Taking a build with the latest finishedAt time");
    }

    my $build = $search_result->{value}->[0];
    return $build->{id};
}

sub find_definition_id_by_name {
    my ( $self, $config, $project, $definition_name ) = @_;
    return unless $definition_name;

    # Make a list request
    my $request_path = $project . '/_apis/build/definitions';
    my $api_version = get_api_version($request_path, $config);
    my $client = $self->get_microrest_client($config);

    my $search_result = $client->get($request_path, {
        'api-version' => $api_version,
        name          => $definition_name
    });

    if (! $search_result || ref $search_result ne 'HASH') {
        $self->bail_out("Failed to find given definition. API returned wrong value. Check errors above");
    }
    if (! $search_result->{count}) {
        $self->bail_out("Failed to find given definition. No definitions found for specified Build Definition Name ($definition_name).");
    }

    my $definition = $search_result->{value}->[0];
    return $definition->{id};
}

sub find_queue_id_by_name {
    my ( $self, $config, $project, $queue_name ) = @_;
    return unless $queue_name;

    # Make a list request
    my $request_path = $project . '/_apis/build/queues';
    my $api_version = get_api_version($request_path, $config);
    my $client = $self->get_microrest_client($config);

    my $search_result = $client->get($request_path, {
        'api-version' => $api_version,
        name          => $queue_name
    });

    if (! $search_result || ref $search_result ne 'HASH') {
        $self->bail_out("Failed to find given query. API returned wrong value. Check errors above");
    }
    if (! $search_result->{count}) {
        $self->bail_out("Failed to find given query. No query was found for specified Query Name ($queue_name).");
    }

    my $queue = $search_result->{value}->[0];
    return $queue->{id};
}

# Client is received in parameters because NTLM authenticates a TCP connection
# This allows to avoid few more auth requests
sub wait_for_build {
    my ( $self, $client, $config, $build_id, $timeout ) = @_;

    $timeout ||= 300;

    my $request_path = '/_apis/build/builds/' . $build_id;
    my $api_version = get_api_version($request_path, $config);

    my $waited = 0;
    my $time_to_sleep = 30;

    my $build_info;
    my $status = 'notStarted';
    while ($status =~ /inProgress|notStarted/i) {
        $build_info = $client->get($request_path, {
            'api-version' => $api_version
        });
        $self->bail_out("Failed receiving build info. Check for errors above") if (! $build_info);

        $status = $build_info->{status};

        if ($status !~ /inProgress|notStarted/i) {
            return $build_info;
        }

        $self->logger->info("Build $build_id ($build_info->{buildNumber}) is still in progress ($status)."
            . " At now waited $waited from $timeout seconds");

        # Check for timeout
        $waited += $time_to_sleep;
        if ($timeout != 0 && $waited >= $timeout) {
            $self->bail_out("Wait operation has timed out, last status: $status");
        }

        sleep($time_to_sleep);
    }

    return $build_info;
}

#@returns EC::Plugin::MicroRest
sub get_microrest_client {
    my ( $self, $config, $content_type ) = @_;

    return EC::Plugin::MicroRest->new(
        url            => $self->get_base_url($config),
        auth           => $config->{auth} || 'basic',
        user           => $config->{userName},
        password       => $config->{password},

        http_proxy     => $config->{http_proxy},
        proxy_username => $config->{proxy_username},
        proxy_password => $config->{proxy_password},

        ctype      => $content_type || 'application/json-patch+json',
        encode_sub => \&encode_json,
        decode_sub => sub {
            $self->decode_json_or_bail_out(shift, "Failed to parse JSON response from $config->{endpoint})")
        }
    );
}

sub parse_generic_create_update_parameters {
    my ( $self, $parameters ) = @_;

    my %generic_fields = ();

    # Map parameters to Azure operations (Update does not contain "type" parameter)
    for my $param (qw/priority assignTo description title type commentBody/) {
        $generic_fields{ lc($param) } = $parameters->{$param} if $parameters->{$param};
    }

    return wantarray ? %generic_fields : \%generic_fields;
}

sub parse_azure_additional_fields {
    my ( $self, $additional_fields ) = @_;

    my @additional_fields_array = ();

    # Check it is JSON
    my $additional_fields_decoded = $self->decode_json_or_bail_out($additional_fields, "Failed to parse Additional Fields.");

    if (ref $additional_fields_decoded eq 'HASH') {
        push @additional_fields_array, $additional_fields_decoded;
    }
    elsif (ref $additional_fields_decoded eq 'ARRAY') {
        push @additional_fields_array, @$additional_fields_decoded;
    }

    for my $field_def (@additional_fields_array) {
        # Default operation (for create or update)
        $field_def->{op} = 'add' if (! $field_def->{op});

        for my $key (qw/value path/) {
            if (! $field_def->{$key}) {
                $self->bail_out("ADOS additional field definition should contain key '$key'. Please refer to the format at the plugin's help.")
            }
        }
    }

    return wantarray ? @additional_fields_array : \@additional_fields_array;
}

sub parse_build_parameters {
    my ( $self, $raw_attributes ) = @_;

    my %pairs = ();

    # Parse given attributes
    eval {
        my @attributes = split('\n', $raw_attributes);
        foreach my $attribute_pair (@attributes) {
            my ( $name, $value ) = split('=', $attribute_pair, 2);
            $pairs{$name} = $value;
        }
        1;
    }
        or do {
        $self->info("Failed to parse custom attributes : $@");
        return 0;
    };

    return \%pairs;
}

sub build_create_multi_entity_payload {
    my ( $self, $parameters, %generic_fields ) = @_;
    my @results = ();

    # If we have Request Body, than this is the only payload
    if ($parameters->{workItemsJSON}) {
        my $err_msg = 'Value for "Work Items JSON" should contain valid non-empty JSON array.';
        my $work_items = $self->decode_json_or_bail_out($parameters->{workItemsJSON}, $err_msg);
        $self->bail_out($err_msg) unless ref($work_items) eq 'ARRAY' && scalar @$work_items;

        my @field_params = ( qw/Type Title Priority Description/, 'Assign To' );

        # JSON object keys are the same as Parameter label
        # Item hash keys are the same as Parameter property names (lower cased)
        for my $predefined_work_item (@$work_items) {
            my %work_item = ();

            for my $key (@field_params) {
                my $search_key = ( $key eq 'Assign To' ) ? 'assignto' : lc($key);
                my $value = $predefined_work_item->{$key} || $generic_fields{$search_key};

                # Skipping undefined fields
                next unless $value;

                $work_item{$search_key} = $value;
            }

            push @results, \%work_item;
        }
    }
    else {
        my %work_item = ();
        for my $wi_field_name (keys %generic_fields) {
            next unless $generic_fields{$wi_field_name};
            $work_item{$wi_field_name} = $generic_fields{$wi_field_name}
        }

        push @results, \%work_item;
    }

    return wantarray ? @results : \@results;
}

sub save_work_items {
    my ( $self, $entities_list, $result_property, $result_format, $transform_sub ) = @_;

    my @ids = $self->save_entities($entities_list, $result_property, $result_format, $transform_sub);
    return unless scalar @ids;

    my $ids_property = $result_property . '/workItemIds';
    my $ids_str = join(', ', @ids);
    $self->logger->info("Work item IDs ($ids_str) will be saved to a property '$ids_property'.");
    $self->ec->setProperty($ids_property, $ids_str);

    return 1;
}

sub save_entities {
    my ( $self, $entities_list, $result_property, $result_format, $transform_sub ) = @_;

    my @ids = ();
    for my $entity (@$entities_list) {
        next if ! $entity;

        if ($transform_sub) {
            $self->logger->debug("Entity to save before transform", $entity);
            $entity = $transform_sub->($self, $entity);
        }

        my $id = $entity->{id};
        push @ids, $id;

        $self->save_parsed_data($entity, $result_property . "/$id", $result_format)
    }

    return wantarray ? @ids : \@ids;
}

sub save_parsed_data {
    my ( $self, $parsed_data, $result_property, $result_format ) = @_;

    unless ($result_format) {
        $self->bail_out('No format has been selected');
    }

    if (!$result_property && $result_format ne 'none'){
        $self->bail_out("Parameter 'Result Property' is mandatory, when 'Result Format' is not a 'Do not save result'");
    }

    unless ($parsed_data) {
        $self->logger->info("Nothing to save");
        return;
    }

    $self->logger->debug("Data to save", JSON->new->pretty->encode($parsed_data));

    if ($result_format eq 'none') {
        $self->logger->info("Results will not be saved to a property");
    }
    elsif ($result_format eq 'propertySheet') {

        my $flat_map = $self->_self_flatten_map($parsed_data, $result_property, 'check_errors!');

        for my $key (sort keys %$flat_map) {
            $self->logger->info("Saving $key -> $flat_map->{$key}");
            $self->ec->setProperty($key, $flat_map->{$key});
        }
    }
    elsif ($result_format eq 'json') {
        my $json = encode_json($parsed_data);
        $json = decode('utf8', $json);
        $self->logger->trace(Dumper($json));
        $self->ec->setProperty($result_property, $json);
        $self->logger->info("Saved answer under $result_property");
    }
    elsif ($result_format eq 'file') {
        #saving data implementation is on Hooks side!
    }
    else {
        $self->bail_out("Cannot process format $result_format: not implemented");
    }
}

sub get_work_items {
    my ( $self, $work_item_ids, $params ) = @_;

    $params ||= {};

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);
    my $api_version = get_api_version('/_apis/wit/workitems/', $config);

    # GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&fields={fields}&asOf={asOf}&$expand={$expand}&errorPolicy={errorPolicy}&api-version=4.1
    my %query_params = (
        'api-version' => $api_version,
        ids           => join(',', @$work_item_ids),

        # Missing items should be handled on our side
        errorPolicy   => 'Omit'
    );


    # Adding optional query parameters
    if ($params->{fields}) {
        my @fields = split(',\s?', $params->{fields});
        my @correct_fields = grep {$_ =~ /^[a-zA-Z\.]+$/} @fields;

        $query_params{fields} = join(',', @correct_fields);
    }
    if ($params->{expandRelations}) {
        $query_params{'$expand'} = $params->{expandRelations};
    }
    if ($params->{asOf}) {
        $query_params{asOf} = $params->{asOf};
    }

    my $result = $client->get("/_apis/wit/workitems", \%query_params);

    return $result;
}

sub upload_chunked {
    my ( $self, $config, %upload_params ) = @_;

    my $client = $self->get_microrest_client($config, 'application/octet-stream');

    # Check the params
    my $file_path = $upload_params{filePath};
    unless (-f $file_path) {
        $self->bail_out("No file found: $file_path");
    }

    my $request_path = '_apis/wit/attachments';
    my $api_version = get_api_version($request_path, $config);

    # Send a request to signal start of a chunked
    $client->{request_hook} = sub {
        my HTTP::Request $request = shift;
        $request->header('Content-Length' => 0);
        $request;
    };

    my $start_response = $client->post($request_path, {
        fileName      => $upload_params{filename},
        uploadType    => 'chunked',
        'api-version' => $api_version
    });

    $self->logger->trace($start_response);

    my $attachment_url = $start_response->{url};
    delete $client->{encode_sub};

    open my $fh, $file_path or $self->bail_out("Cannot open $file_path: $!");
    my $cl_start = 0;

    my $buf;
    my $total = -s $file_path;
    $self->logger->debug("Total size: $total bytes");

    my $cl_end = 0;
    my $total_mb = $total / ( 1024 * 1024 );

    my URI $attachment_upload_uri = URI->new($attachment_url);

    my $attachment_path = $attachment_upload_uri->path();
    $attachment_path =~ s|.*?_apis/wit/|_apis/wit/|;

    # NTLM via proxy requires to add a special header
    my $ntlm_and_proxy = ($client->{proxy} && $client->get_auth eq 'ntlm');
    if ($ntlm_and_proxy){
        $self->logger->info("[WARNING] Using both NTLM auth and a proxy,"
         . " can cause upload to be crashed with 'Unauthorized' error if"
         . " your Proxy does not keeps persistent connections for"
         . " the POST requests (as Squid 3.5.27 does).")
    }

    my $upload_crashed = 0;
    my $chunk_size = 1024 * 1024; # 1 MB
    while (my $bytes_read = read($fh, $buf, $chunk_size)) {
        $cl_end = $bytes_read - 1 + $cl_start;
        my $content_length = "$cl_start-$cl_end";

        $client->{request_hook} = sub {
            my HTTP::Request $request = shift;
            $request->header('Content-Range' => "bytes $content_length/$total");
            $request->header('Content-Type' => "application/octet-stream");
            $request->header('Proxy-Connection' => "Keepalive") if ($ntlm_and_proxy);
            $request->content($buf);
            $request;
        };

        eval {
          $client->post($attachment_path, {
              fileName      => $upload_params{filename},
              'api-version' => $api_version
          });
        } or do {
            $upload_crashed = $@;
        };
        last if $upload_crashed;

        $cl_start += $bytes_read;
        my $uploaded_mb = $cl_start / ( 1024 * 1024 );
        $self->logger->debug(sprintf "Upload progress: %.2f/%.2f Mb", $uploaded_mb, $total_mb);
    }

    if ($upload_crashed){
        $self->logger->error("Upload process has been interrupted with error: " . $upload_crashed);
        return;
    }

    $self->logger->debug('Upload finished');

    return $attachment_url;
}

sub upload_simple {
    my ( $self, $config, %upload_params ) = @_;

    my $client = $self->get_microrest_client($config, 'application/octet-stream');
    delete $client->{encode_sub};

    my $request_path = '_apis/wit/attachments';
    my $api_version = get_api_version($request_path, $config);

    my $content;
    my $content_length;
    if ($upload_params{filePath}) {
        if (! -f $upload_params{filePath}) {
            $self->bail_out("Can't find file: " . $upload_params{filePath});
        }

        open(my $fh, '<', $upload_params{filePath})
            or $self->bail_out("Failed to read the file '$upload_params{filePath}': $@");

        $content_length = -s $upload_params{filePath};

        # Read the full file
        read($fh, $content, $content_length);
    }
    elsif ($upload_params{fileContent}) {
        $content = $upload_params{fileContent};
        $content_length = length $content;
    }
    else {
        $self->bail_out("Either 'File Path' or a 'File Content' should be specified.");
    }

    $client->{request_hook} = sub {
        my HTTP::Request $request = shift;
        $request->header('Content-Length' => $content_length);
        $request;
    };

    my $response = $client->post($request_path,
        {
            fileName      => $upload_params{filename},
            uploadType    => 'simple',
            'api-version' => $api_version
        },
        $content
    );

    return $response->{url};
}

sub get_base_url {
    my ( $self, $config ) = @_;

    $config ||= $self->{_config};
    $self->bail_out("No configuration was given to EC::AzureDevOps::Plugin\n") unless ($config);

    # Check mandatory
    for my $param (qw/endpoint collection/) {
        $self->bail_out("No value for configuration parameter '$param' was provided\n") unless $config->{$param};
    }

    # Strip value
    $config->{endpoint} =~ s|/+$||g;
    $config->{collection} =~ s|/+$||g;

    return "$config->{endpoint}/$config->{collection}";
}

sub _parse_api_versions {
    my ( $string ) = @_;

    my @lines = split(/\n+/, $string);
    my %retval = map {my ( $key, $value ) = split(/\s*=\s*/, $_)} grep {$_} @lines;
    return \%retval;
}

sub get_api_version {
    my ( $uri, $config ) = @_;

    if ($config->{apiVersion} ne 'custom') {
        return $config->{apiVersion};
    }

    my $api_versions = _parse_api_versions($config->{customApiVersions});
    my ( $first_name, $second_name ) = $uri =~ m{/_apis/(\w+)/(\w+)};
    my $version = $api_versions->{"$first_name/$second_name"} || '1.0';

    return $version;
}

sub _generate_field_op_hash {
    my ( $field_name, $field_value, $operation ) = @_;

    $operation ||= 'add';

    return { op => $operation, path => '/fields/' . $MS_FIELDS_MAPPING{lc($field_name)}, value => $field_value }
}

sub _self_flatten_map {
    my ( $self, $map, $prefix, $check ) = @_;

    if (defined $check and $check) {
        $check = 1;
    }
    else {
        $check = 0;
    }
    $prefix ||= '';
    my %retval = ();

    for my $key (keys %$map) {

        my $value = $map->{$key};
        if (ref $value eq 'ARRAY') {
            my $counter = 1;
            my %copy = map {my $key = ref $_ ? $counter ++ : $_;
                $key => $_} @$value;
            $value = \%copy;
        }
        if (ref $value ne 'HASH') {
            $value = '' unless defined $value;
            $value = "$value";
        }
        if (ref $value) {
            if ($check) {
                foreach my $bad_key (FORBIDDEN_FIELD_NAME_PROPERTY_SHEET) {
                    if (exists $value->{$bad_key}) {
                        $self->_fix_propertysheet_forbidden_key($value, $bad_key);
                    }
                }
            }

            %retval = ( %retval, %{$self->_self_flatten_map($value, "$prefix/$key", $check)} );
        }
        else {
            if ($check) {
                foreach my $bad_key (FORBIDDEN_FIELD_NAME_PROPERTY_SHEET) {
                    if ($key eq $bad_key) {
                        $self->_fix_propertysheet_forbidden_key(\$key, $bad_key);
                    }
                }
            }

            $retval{"$prefix/$key"} = $value;
        }
    }
    return \%retval;
}

sub _transform_work_item {
    my ( $self, $work_item ) = @_;

    delete $work_item->{_links} if $work_item->{_links};

    # Moving 'fields' values to the top level
    my %fields_copy = %{$work_item->{fields}};
    delete $work_item->{fields};
    $work_item = { %$work_item, %fields_copy };

    return $work_item;
}

sub _transform_delete_result {
    my ( $self, $delete_result ) = @_;

    # Delete result contains a deleted work item in a 'resource' property
    my $entity = $delete_result->{resource};

    return $self->_transform_work_item($entity);
}

sub _transform_build_result {
    my ( $self, $build ) = @_;

    # Removing obsolete fields
    my @deep_fields = qw/logs definition _links project
        requestedBy queue repository
        lastChangedBy plans requestedFor
        orchestrationPlan/;

    for my $key (@deep_fields) {
        if ($build->{$key} && ref $build->{$key} eq 'HASH' && $build->{$key}->{name}) {
            $build->{$key} = $build->{$key}->{name};
        }
        else {
            delete $build->{$key};
        }
    }

    return $build;
}

sub _fix_propertysheet_forbidden_key {
    my ( $self, $ref_var, $key ) = @_;

    $self->logger->info("\"$key\" is the system property name", "Prefix FORBIDDEN_FIELD_NAME_PREFIX was added to prevent failure.");
    my $new_key = FORBIDDEN_FIELD_NAME_PREFIX . $key;
    if (ref($ref_var) eq 'HASH') {
        $ref_var->{$new_key} = $ref_var->{$key};
        delete $ref_var->{$key};
    }
    elsif (ref($ref_var) eq 'SCALAR') {
        $$ref_var = $new_key;
    }
}

sub _date_time_check {
    my ( $label, $value ) = @_;

    return unless $value;
    # 2009-06-15T13:45:30
    my $regexp = qr/\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2})?/;
    if ($value =~ $regexp) {
        return 1;
    }
    else {
        return "$label has wrong date format '$value', but should be in ISO 8601 e.g. ('2019-06-15T13:45:30')";
    }
}

sub _number_array_check {
    my ( $label, $value ) = @_;

    return unless $value;

    my @list = split(',\s?', $value);
    if (grep {$_ !~ /^\d+$/} @list) {
        return( 0, "Parameter '$label' should contain a comma-separated list of numbers. Got '$value'" );
    }

    return 1;
}

sub debug_level {
    my ( $self, $debug_level ) = @_;

    # Set new debug level
    if (defined $debug_level) {
        $self->{_init}->{debug_level} = $debug_level;
        return $debug_level;
    }
    # Return existing debug level
    elsif (defined $self->{_init}->{debug_level}) {
        return $self->{_init}->{debug_level};
    }
    # Get debug level from config and save the value
    else {
        my $config_value = 0;

        if (! $self->{_config}) {
            # Trying to get config name from current running procedure parameters
            eval {
                # This methods will use logger, so have to specify temprorary value
                $self->{_init}->{debug_level} = 0;
                my $config_name = $self->get_param('config');
                $self->{_config} = $self->get_config_values($config_name);
                $config_value = $self->{_config}->{debugLevel} || 0;
                1;
            } or do {
                print "Failed to read Log Level from a configuration. Value 0 (Info) will be used.\n";
                $config_value = 0;
            }
        }
        else {
            $config_value = $self->{_config}->{debugLevel} || 0;
        }

        $self->{_init}->{debug_level} = $config_value;
    }

    return $self->{_init}->{debug_level};
}

sub check_connection {
    my ($self, $config) = @_;

    my $client = $self->get_microrest_client($config);
    my $request_path = '_apis/projects';
    my $api_version = get_api_version($request_path, $config);


    my $ok = 0;
    eval {
        my $response = $client->get($request_path, {
            '&$top'       => 1,
            'api-version' => $api_version
        });

        $ok = exists $response->{count};
    };

    return $ok;
}

1;