import groovy.transform.BaseScript
import com.electriccloud.commander.dsl.util.BasePlugin

//noinspection GroovyUnusedAssignment
@BaseScript BasePlugin baseScript

// Variables available for use in DSL code
def pluginName = args.pluginName
def upgradeAction = args.upgradeAction
def otherPluginName = args.otherPluginName

def pluginKey = getProject("/plugins/$pluginName/project").pluginKey
def pluginDir = getProperty("/projects/$pluginName/pluginDir").value

//List of procedure steps to which the plugin configuration credentials need to be attached
// ** steps with attached credentials
def stepsWithAttachedCredentials = [
    // Rewritten ones
    [procedureName: 'CreateWorkItems', stepName: 'create work items'],
    [procedureName: 'UpdateWorkItems', stepName: 'update work items'],
    [procedureName: 'DeleteWorkItems', stepName: 'delete work items'],
    [procedureName: 'GetWorkItems', stepName: 'get work items'],
    [procedureName: 'QueryWorkItems', stepName: 'query work items'],
    [procedureName: 'GetDefaultValues', stepName: 'get default values'],
    [procedureName: 'UploadWorkItemAttachment', stepName: 'upload a work item attachment'],
    [procedureName: 'GetBuild', stepName: 'get a build'],
    [procedureName: 'TriggerBuild', stepName: 'trigger a build'],
    [procedureName: 'CollectReportingData', stepName: 'collect reporting data'],
]
// ** end steps with attached credentials

// Deleting the step pickers
def unavailableProcedures = [
    // Query is moved out of the scope
    [procedureName: 'CreateWorkItems Query', stepName: 'create work items query'],
    [procedureName: 'DeleteWorkItems Query', stepName: 'delete work items query'],
    [procedureName: 'Run a Work Item Query', stepName: 'run a work item query'],
    [procedureName: 'UpdateWorkItems Query', stepName: 'updates a work item query'],

    // Git operations should be done in ECSCM plugin
    [procedureName: 'Download an Artifact from a Git Repository', stepName: 'download an artifact from a git repository'],

    // Procedure was renamed
    [procedureName: 'Query a build', stepName: 'query a build'],
    [procedureName: 'Get a List of Work Items', stepName: 'get a list of work items'],
    [procedureName: 'Query Work Items', stepName: 'query work items'],
    [procedureName: 'Get Default Values', stepName: 'get default values'],
    [procedureName: 'Upload a Work Item Attachment', stepName: 'upload a work item attachment'],
    [procedureName: 'Get a Build', stepName: 'get a build'],

    // Single entity operations were refactored to multiple entity operations
    [procedureName: 'Create a Work Item', stepName: 'create a work item'],
    [procedureName: 'Update a Work Item', stepName: 'update a work item'],
    [procedureName: 'Get a Work Item', stepName: 'get a work item'],
    [procedureName: 'Delete a Work Item', stepName: 'delete a work item'],
]

project pluginName, {

    unavailableProcedures.each { p ->
        deleteStepPicker((String) pluginKey, (String) p.procedureName)
    }

    loadPluginProperties(pluginDir, pluginName)
    loadProcedures(pluginDir, pluginKey, pluginName, stepsWithAttachedCredentials)

    //plugin configuration metadata
    property 'ec_config', {
        configLocation = 'ec_plugin_cfgs'
        form = '$[' + "/projects/${pluginName}/procedures/CreateConfiguration/ec_parameterForm]"
        property 'fields', {
            property 'desc', {
                property 'label', value: 'Description'
                property 'order', value: '1'
            }
        }
    }

    property 'ec_formXmlCompliant', value : "true"

    property 'ecp_azuredevops_workitemtypes', {
        property 'Bug', value: 'Bug'
        property 'Epic', value: 'Epic'
        property 'Feature', value: 'Feature'
        property 'Issue', value: 'Issue'
        property 'User Story', value: 'User Story'
    }
}

// Copy existing plugin configurations from the previous
// version to this version. At the same time, also attach
// the credentials to the required plugin procedure steps.
upgrade(upgradeAction, pluginName, otherPluginName, stepsWithAttachedCredentials)
