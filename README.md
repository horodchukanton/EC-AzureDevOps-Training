# EC-TFS

This plugin allows to work with REST API of Visual Studio Team Services/Team Foundation Server.


# Procedures

## Get a List of Work Items

Retrieves a list of the work items.

## Create a Work Item

Creates a new work item.

## Update a Work Item

Update a work item fields.

## Get a Work Item

Returns the content of the work item

## Delete a Work Item

Deletes the specified work item.

## Get Default Values

Get the default values that will be filled in automatically when you create a new work item of a specific type.

## Create a Work Item Query

Create a new work item search query.

## Update a Work Item Query

Updates a work item search query.

## Run a Work Item Query

Runs a new work item search query.

## Delete a Work Item Query

Deletes the specified work item search query.

## Queue a build

Queues a new build.

## Upload a Work Item Attachment

To attach a file to a work item, upload the attachment to the attachment store, then attach it to the work item.

## Download an Artifact from a Git Repository

Downloads a file from a Git repository.

## Get a Build

Gets a specified build info



# Building the plugin
1. Download or clone the EC-TFS repository.

    ```
    git clone https://github.com/electric-cloud/EC-TFS.git
    ```

5. Zip up the files to create the plugin zip file.

    ```
     cd EC-TFS
     zip -r EC-TFS.zip ./*
    ```

6. Import the plugin zip file into your ElectricFlow server and promote it.
