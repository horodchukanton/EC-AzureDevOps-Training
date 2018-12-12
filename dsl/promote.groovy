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
  [procedureName: 'Create a Work Item', stepName: 'create a work item'],
  [procedureName: 'Delete a Work Item', stepName: 'delete a work item'],
  [procedureName: 'Get Default Values', stepName: 'get default values'],
  [procedureName: 'Get a List of Work Items', stepName: 'get a list of work items'],
  [procedureName: 'Get a Work Item', stepName: 'get a work item'],
  [procedureName: 'Queue a build', stepName: 'queue a build'],
  [procedureName: 'Update a Work Item', stepName: 'update a work item'],
]
// ** end steps with attached credentials

// Deleting the step pickers
def unavailableProcedures = [
	[procedureName: 'Create a Work Item Query', stepName: 'create a work item query'],
	[procedureName: 'Delete a Work Item Query', stepName: 'delete a work item query'],
	[procedureName: 'Download an Artifact from a Git Repository', stepName: 'download an artifact from a git repository'],
	[procedureName: 'Get a Build', stepName: 'get a build'],
	[procedureName: 'Query Work Items', stepName: 'query work items'],
	[procedureName: 'Run a Work Item Query', stepName: 'run a work item query'],
	[procedureName: 'Update a Work Item Query', stepName: 'updates a work item query'],
	[procedureName: 'Upload a Work Item Attachment', stepName: 'upload a work item attachment']
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
}

// Copy existing plugin configurations from the previous
// version to this version. At the same time, also attach
// the credentials to the required plugin procedure steps.
upgrade(upgradeAction, pluginName, otherPluginName, stepsWithAttachedCredentials)
