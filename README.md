# EC-AzureDevOps

This plugin allows to work with REST API of AzureDevOps Server/Services (former TFS/VSTS).


# Procedures

## GetWorkItems

Retrieves a list of the work items.

## CreateWorkItems

Creates a new work item.

## UpdateWorkItems

Update a work item fields.

## Get a Work Item

Returns the content of the work item

## DeleteWorkItems

Deletes the specified work item.

## Get Default Values

Get the default values that will be filled in automatically when you create a new work item of a specific type.

## TriggerBuild

Queues a new build.

## GetaBuild

Get information about a build.

## Upload a Work Item Attachment

To attach a file to a work item, upload the attachment to the attachment store, then attach it to the work item.



# Building the plugin
1. Download or clone the EC-AzureDevOps repository.

    ```
    git clone https://github.com/electric-cloud/EC-AzureDevOps.git
    ```

5. Zip up the files to create the plugin zip file.

    ```
     cd EC-AzureDevOps
     zip -r EC-AzureDevOps.zip ./*
    ```

6. Import the plugin zip file into your ElectricFlow server and promote it.
