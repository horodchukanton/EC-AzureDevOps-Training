use strict;
use warnings FATAL => 'all';

use ElectricCommander;
use EC::AzureDevOps::Plugin;
use JSON;

main();
exit 0;

sub get_step_parameters {
    my ($plugin_instance) = @_;

    my $parameters = {};
    my $procedure_name = $plugin_instance->ec->getProperty('/myProcedure/name')->findvalue('//value')->string_value;
    my $xpath = $plugin_instance->ec->getFormalParameters({projectName => '@PLUGIN_NAME@', procedureName => $procedure_name});
    for my $param ($xpath->findnodes('//formalParameter')) {
        my $name = $param->findvalue('formalParameterName')->string_value;
        my $value = $plugin_instance->get_param($name);

        my $name_in_list = $name;
        if ($param->findvalue('type')->string_value eq 'credential') {
            my $cred = $plugin_instance->ec->getFullCredential($value);
            my $username = $cred->findvalue('//userName')->string_value;
            my $password = $cred->findvalue('//password')->string_value;

            $parameters->{$name_in_list . 'Username'} = $username;
            $parameters->{$name_in_list . 'Password'} = $password;
        }
        else {
            $parameters->{$name_in_list} = EC::Plugin::Core::trim_input($value);
            $plugin_instance->out(1, qq{Got parameter "$name" with value "$value"\n});
        }
    }
    return $parameters;
}

sub check_parameters {
    my ($plugin, $params) = @_;

    # Checking required parameters value
    # This is controlled by UI but we also have DSL and special values, like '$[]'
    my @required = qw/config/;
    for my $parameter_name (@required){
        if (! $params->{$parameter_name}){
            $plugin->bail_out("No value for the required parameter '$parameter_name'.");
            return 0;
        }
    }

    if ( !($params->{queryId} || $params->{queryText})
       || ($params->{queryId} && $params->{queryText})
    ){
        $plugin->bail_out("Either the 'Query Id' or 'Query Text' should be specified.");
    }

    return 1;
}

## Query by ID reference
# https://docs.microsoft.com/uk-ua/rest/api/azure/devops/wit/wiql/query%20by%20id?view=azure-devops-rest-4.1
## Query by WIQL reference
# https://docs.microsoft.com/uk-ua/rest/api/azure/devops/wit/wiql/query%20by%20wiql?view=azure-devops-rest-4.1
## Query Work Items by IDs
# https://docs.microsoft.com/uk-ua/rest/api/azure/devops/wit/work%20items/list?view=azure-devops-rest-4.1
sub get_report_entities {
    my ($plugin, $config, $params) = @_;

    my $microrest = $plugin->get_microrest_client($config, 'application/json');

    # Defining where request should go
    # AzureDevOps specific! Hardcoded api-version
    my $api_version = '4.1';

    # The request differs for the Query ID and Query Text
    my $response = undef;
    if ($params->{queryText}) {
        $response = $microrest->post(
            '/_apis/wit/wiql',
            {
                'timePrecision' => 'true',
                'api-version'   => $api_version
            },
            { query => $params->{queryText} }
        );
    }
    elsif ($params->{queryId}) {
        $response = $microrest->get(
            '_apis/wit/wiql/' . $params->{queryId},
            {
                'timePrecision' => 'true',
                'api-version'   => $api_version
            }
        );
    }

    $plugin->logger->debug("RESPONSE", $response);

    ## A note about AzureDevOps API response.
    #  The result of the search query does not contain
    #  items itself, but only the reference to the items
    # (**Captain Jack Sparrow with a drawing of a key goes here**)

    my @ids = map {$_->{id}} @{$response->{workItems}};
    $plugin->logger->info("IDs of the found work items: " . join(', ', @ids));

    # So now we can request the items itself
    # I'm using plugin method
    my $work_items_result = $microrest->get(
        '/_apis/wit/workitems',
        {
            'api-version' => '4.1',
            ids           => join(',', @ids),
            errorPolicy   => 'Fail'
        }
    );

    # Note that items itself are in the 'value' key
    $plugin->logger->debug("WORK ITEMS RESULT", $work_items_result);

    return $work_items_result->{value};
}

sub analyze_items {
    my ($plugin, $params, $items) = @_;

    # Should be the same as the ec_devops_insight/feature/source property value
    my $sourceName = 'AzureDevOps';

    # TODO: metadata and timestamp check
    # my $metadata_property = $params->{metadataPropertyPath} || calculate_the_metadata_property_path($plugin);
    # my $metadata = $plugin->ec->get_property($metadata_property);

    # TODO: get a releaseName
    my $releaseName = 'AzureDevOpsRelease';
    my $releaseProjectName = 'AzureDevOps';

    my @payload = ();
    for my $item (@$items){
        $plugin->logger->debug("Transforming the source item", $item);

        # TODO: move to a separate procedure
        # This is mappings part
        my $feature_name = $item->{fields}->{'System.Title'};
        my $modified_time= $item->{fields}->{'Microsoft.VSTS.Common.StateChangeDate'};
        my $created_time = $item->{fields}->{'System.CreatedDate'};
        my $type         = $item->{fields}->{'System.WorkItemType'};
        my $source_url   = $item->{url};
        my $status       = ( $item->{fields}->{'System.State'} eq 'Active' ) ? "Open" : "Closed";

        # TODO: Check if this is a correct resolution
        my $resolution   = ( $item->{fields}->{'System.State'} eq 'Active' ) ? "Fixed" : "Open";

        push (@payload, {
            "releaseName"         => $releaseName,
            "source"              => $sourceName,
            "featureName"         => $feature_name,
            "status"              => $status,
            "pluginConfiguration" => $params->{config},
            "modifiedOn"          => $modified_time,
            "key"                 => $item->{id},
            "pluginName"          => '@PLUGIN_NAME',
            "timestamp"           => $modified_time,
            "releaseUri"          => "",
            "releaseProjectName"  => $releaseProjectName,
            "resolution"          => $resolution,
            "type"                => $type,
            "createdOn"           => $created_time,
            "sourceUrl"           => $source_url
        });
    }

    return \@payload;
}

sub main {
    # Initialize the plugin object instance
    my $plugin = EC::AzureDevOps::Plugin->new();
    $plugin->logger->info("Hello, world");

    # Get the job parameters.
    my $params = get_step_parameters($plugin);

    if ($params->{debug} && $plugin->logger->level < 1) {
        $plugin->logger->level(1);
    }

    # Checking the parameters
    check_parameters($plugin, $params)
      or die "Parameters check failed";

    # Get configuration values
    my $config = $plugin->get_config_values($params->{config});

    # Request the entities
    my $entities = get_report_entities($plugin, $config, $params);

    # If necessary, filter the results to exclude the duplicate items.
    ## TODO: we can specify a timestamp in the query (add a parameter?)

    # Transform the raw data to the standardized one.
    my $report_payload = analyze_items($plugin, $params, $entities);
    my $report_object_type = 'feature';

    # Send the data to EC.
    my $payloads_sent_count = 0;
    for my $payload (@$report_payload){

        # Show pretty in logs
        my $beautified_payload = JSON->new->pretty->utf8()->encode($payload);
        $plugin->logger->info("Preview of the payload", $beautified_payload);
        next if $params->{preview};

        # Send compact
        $plugin->ec->sendReportingData({
            payload              => JSON->new->encode($payload),
            reportObjectTypeName => $report_object_type
        });

        $payloads_sent_count++;
    }

    $plugin->success("$payloads_sent_count payloads sent.");

    return 1;
}

exit 0;