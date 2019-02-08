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

    $plugin->logger->debug("WORK ITEMS RESULT", $work_items_result);

    return $work_items_result;
}

sub analyze_items {
    my ($plugin, $params, $items) = @_;

    # TODO: metadata
    # my $metadata_property = $params->{metadataPropertyPath} || calculate_the_metadata_property_path($plugin);
    # my $metadata = $plugin->ec->get_property($metadata_property);

    my @payload = ();
    # for my $item (@$items){
        push @payload, {
            "releaseName"         => "EC-AzureDevOps",
            "source"              => "AzureDevOps",
            "featureName"         => "Run Sanity, E2E and New Feature on ALL Windows",
            "status"              => "Closed",
            "pluginConfiguration" => "test",
            "modifiedOn"          => "2018-11-08T14:59:53.000Z",
            "key"                 => "ECJIRA-146",
            "pluginName"          => "EC-JIRA",
            "timestamp"           => "2018-11-08T14:59:53.000Z",
            "releaseUri"          => "",
            "releaseProjectName"  => "Default",
            "resolution"          => "Fixed",
            "baseDrilldownUrl"    => "http://jira.electric-cloud.com/issues/?jql=issuetype%20=%20Story%20AND%20project%20=%20ECJIRA",
            "type"                => "Story",
            "createdOn"           => "2018-10-29T16:15:50.000Z",
            "sourceUrl"           => "http://jira.electric-cloud.com/browse/ECJIRA-146"
        };
    # }

    return \@payload;
}

sub main {
    # Initialize the plugin object instance
    my $plugin = EC::AzureDevOps::Plugin->new();
    $plugin->logger->info("Hello, world");

    # Get the job parameters.
    my $params = get_step_parameters($plugin);

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
    my $report_payload = analyze_items($plugin, $entities);
    my $report_object_type = 'feature';

    if ($params->{preview}){
        my $beautified_payload = JSON->new->pretty->utf8()->encode($report_payload);
        $plugin->logger->info("Preview of the payload", $beautified_payload);
        $plugin->logger->info("[PREVIEW MODE] Exit without the payload sending");

        return 1;
    }

    $plugin->logger->debug($report_payload);

    # Send the data to EC.
    $plugin->ec->sendReportingData({
        payload              => JSON->new->encode($report_payload),
        reportObjectTypeName => $report_object_type
    });

    return 1;
}

exit 0;