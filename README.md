# EC-AzureDevOps-Training

This plugin allows to work with REST API of AzureDevOps Server/Services (former TFS/VSTS).


# Procedures

## GetWorkItems

Retrieves a list of the work items.

## CreateWorkItems

Creates a new work item.

## UpdateWorkItems

Update a work item fields.

## DeleteWorkItems

Deletes the specified work item.

## QueryWorkItems

Performs a search inside a TFS using given WIQL query (or existing query), then saves found work items into the properties.

## GetDefaultValues

Get the default values that will be filled in automatically when you create a new work item of a specific type.

## TriggerBuild

Queues a new build.

## GetBuild

Get information about a build.

## Upload a Work Item Attachment

To attach a file to a work item, upload the attachment to the attachment store, then attach it to the work item.

# Building the plugin
1. Download or clone the EC-AzureDevOps-Training repository.

    ```
    git clone https://github.com/electric-cloud/EC-AzureDevOps-Training.git
    ```

5. Use the [ecpluginbuilder](https://github.com/electric-cloud/ecpluginbuilder) to format and build the plugin.

    ```
     cd EC-AzureDevOps-Training
     ecpluginbuilder --plugin-version 1.0.0 --plugin-name EC-AzureDevOps-Training --folder dsl,htdocs,pages,META-INF
    ```

6. Import the plugin zip file into your ElectricFlow server and promote it.
