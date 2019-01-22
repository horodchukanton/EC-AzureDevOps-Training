package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import spock.lang.*

@Stepwise
class GetBuild extends PluginTestHelper {

    static String procedureName = "GetBuild"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName
//    @Shared
    def project
//    @Shared
    def buildId
    @Shared
    def resultPropertySheet = '/myJob/build'
    @Shared
    def resultFormat = 'propertySheet'

    // Optional
//    @Shared
    def waitForBuild
    def buildDefinitionName
//    @Shared
    def waitTimeout

    /// Specs parameters
    @Shared
    def caseId,
        expectedSummary,
        expectedOutcome

    static definitionName = getAssertedEnvVariable("BUILD_DEFINITION_NAME")

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient
    }

    def doCleanupSpec() {
        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    // This one goes first to avoid timeout if have to wait for other builds to finish
    @Unroll
    def "#caseId. Sanity. Get Build with waiting"() {
        given:
        def resultJobPropertyName = 'build'
        resultPropertySheet = '/myJob/' + resultJobPropertyName
        resultFormat = 'propertySheet'

        waitForBuild = 1
        // Successful dry-run build runs runs 15 seconds on TFS and 60 on Azure.
        // Waiting three times longer to assume previous build has finished
        waitTimeout = 10 + (60 * 3)

        project = getADOSProjectName()

        def build = tfsClient.triggerBuild(buildDefinitionName)
        buildId = build.id
        assert buildId

        def procedureParams = [
            config             : config,
            project            : project,
            buildId            : buildId,
            buildDefinitionName: buildDefinitionName,
            waitForBuild       : waitForBuild,
            waitTimeout        : waitTimeout,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)

        assert result.outcome == 'success'
        def jobProperties = getJobProperties(result.jobId)

        Map buildInfo = (Map) jobProperties[resultJobPropertyName]

        // Assert that build is finished
        assert buildInfo['status'] == 'completed'

        // Simply assert we received same build
        assert Integer.valueOf((String) buildInfo['id']) == Integer.valueOf((String) build.id)

        cleanup:
        if (build.id && build.id) {
            logger.debug("Waiting for build to finish")
            tfsClient.waitForBuild(build.id, 120)
        }
        where:
        caseId       | requestBy | buildDefinitionName
        'CHANGEME_1' | 'id'      | definitionName
    }

    @Unroll
    def "#caseId. Sanity. Get Build without wait"() {
        given:
        def resultJobPropertyName = 'build'
        resultPropertySheet = '/myJob/' + resultJobPropertyName
        resultFormat = 'propertySheet'

        project = getADOSProjectName()

        def build = tfsClient.triggerBuild(buildDefinitionName)
        if (requestBy == 'id') {
            buildId = build.id
        } else {
            buildId = build.buildNumber
        }
        assert buildId

        def procedureParams = [
            config             : config,
            project            : project,
            buildId            : buildId,
            buildDefinitionName: buildDefinitionName,
            waitForBuild       : waitForBuild,
            waitTimeout        : waitTimeout,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)

        assert result.outcome == 'success'

        Map buildInfo = (Map) jobProperties[resultJobPropertyName]

        // Assert that build is finished
        assert buildInfo['status'] =~ 'inProgress|notStarted|completed'

        // Simply assert we received same build
        assert Integer.valueOf((String) buildInfo['id']) == Integer.valueOf((String) build.id)

        cleanup:
        if (build.id && build.id) {
            logger.debug("Waiting for build to finish")
            tfsClient.waitForBuild(build.id, 120)
        }

        where:
        caseId       | requestBy | buildDefinitionName
        // Here same build can be used
        'CHANGEME_2' | 'id'      | definitionName
        'CHANGEME_3' | 'number'  | definitionName
    }

}