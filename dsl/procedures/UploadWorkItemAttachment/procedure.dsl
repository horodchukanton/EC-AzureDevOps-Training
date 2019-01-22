procedure 'UploadWorkItemAttachment', description: 'To attach a file to a work item, upload the attachment to the attachment store, then attach it to the work item', { // [PROCEDURE]
    // [REST Plugin Wizard step]

    step 'upload a work item attachment',
        command: """
\$[/myProject/scripts/preamble]
use EC::AzureDevOps::Plugin;
EC::AzureDevOps::Plugin->new->step_upload_work_item_attachment();
""",
        errorHandling: 'failProcedure',
        exclusiveMode: 'none',
        releaseMode: 'none',
        shell: 'ec-perl',
        timeLimitUnits: 'minutes'
    
    // [REST Plugin Wizard step ends]

}
