def projName = args.projectName
def procName = 'UploadWorkItemAttachment'

def parameters = [
    config             : '',
    workItemId         : '',
    comment            : '',
    filename           : '',
    uploadType         : '',
    filePath           : '',
    fileContent        : '',
    resultFormat       : '',
    resultPropertySheet: ''
]

project projName, {
    procedure procName, {

        step procName, {
            description = ''
            subprocedure = procName
            subproject = '/plugins/EC-AzureDevOps/project'
            subpluginKey = 'EC-AzureDevOps'
            projectName = projName

            parameters.each { k, v ->
                actualParameter k, (parameters[k] ?: '$[' + k + ']')
            }
        }

        parameters.each { k, defaultValue ->
            formalParameter k, defaultValue: defaultValue, {
                type = 'textarea'
            }
        }
    }
}
