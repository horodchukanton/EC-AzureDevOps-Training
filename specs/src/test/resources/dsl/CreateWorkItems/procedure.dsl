def projName = args.projectName
def procName = 'CreateWorkItems'

def parameters = [
    config             : '',
    project            : '',
    type               : '',
    title              : '',
    priority           : '',
    assignTo           : '',
    description        : '',
    additionalFields   : '',
    workItemsJSON      : '',
    resultPropertySheet: '',
    resultFormat       : ''
]

project projName, {
    procedure procName, {

        step procName, {
            description = ''
            subprocedure = procName
            subproject = '/plugins/EC-AzureDevOps-Training/project'
            subpluginKey = 'EC-AzureDevOps-Training'
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
