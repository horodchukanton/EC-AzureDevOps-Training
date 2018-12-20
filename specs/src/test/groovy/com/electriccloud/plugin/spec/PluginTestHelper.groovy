package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper

/*

Copyright 2018 Electric Cloud, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

*/

import com.electriccloud.spec.*

class PluginTestHelper extends PluginSpockTestSupport {

    static String PLUGIN_NAME = 'EC-AzureDevOps'
    static String automationTestsContextRun = System.getenv('AUTOMATION_TESTS_CONTEXT_RUN') ?: ''
    static String pluginVersion = System.getenv('PLUGIN_VESION') ?: ''

    static String CONFIG_NAME = 'specConfig'

    def createConfiguration(String configName, Map props = [:]) {

        String username = getADOSUsername()
        String password = getADOSPassword()
        String url = getADOSURL()

//        def isProxyAvailable = System.getenv('IS_PROXY_AVAILABLE') ?: '0'
//        def efProxyUrl = System.getenv('EF_PROXY_URL') ?: ''
//        def efProxyUsername = System.getenv('EF_PROXY_USERNAME') ?: ''
//        def efProxyPassword = System.getenv('EF_PROXY_PASSWORD') ?: ''

        if (System.getenv('RECREATE_CONFIG')) {
            props.recreate = true
        }

        /*if (isProxyAvailable != '0') {
            def confPath = props.confPath ?: 'ec_plugin_cfgs'
            if (doesConfExist("/plugins/EC-JIRA/project/$confPath", configName)) {
                if (props.recreate) {
                    deleteConfiguration("EC-JIRA", configName)
                } else {
                    println "Configuration $configName exists"
                    return
                }
            }

            def result = dsl """
            runProcedure(
                projectName: '/plugins/EC-JIRA/project',
                procedureName: 'CreateConfiguration',
                credential: [
                    [
                        credentialName: 'proxy_credential',
                        userName: '$efProxyUsername',
                        password: '$efProxyPassword'
                    ],
                    [
                        credentialName: 'credential',
                        userName: '$username',
                        password: '$password'
                    ],
                ],
                actualParameter: [
                    url             : '$url',
                    config          : '$configName',
                    credential      : 'credential',
                    auth            : '$authType',
                    consumer_key    : '$oauthConsumerKey',
                    http_proxy      : '$efProxyUrl',
                    proxy_credential: 'proxy_credential'
                ]
            )
            """
            assert result?.jobId
            waitUntil {
                jobCompleted(result)
            }
            assert jobStatus(result.jobId).outcome == 'success'
        } // There is no proxy, regular creation.
        else {
*/
        createPluginConfiguration(
            'EC-JIRA',
            configName,
            [
                url        : url,
                desc       : 'Spec Tests Config',
                endpoint   : url,
                collection : getADOSCollectionName(),
                apiVersions: '',
//                    auth        : authType,
//                    consumer_key: oauthConsumerKey
            ],
            username,
            password,
            props
        )
        /*}*/
    }

    static String getAsserted

    static String getADOSUsername() {
        String username = System.getenv('ADOS_USERNAME')
        assert username
        return username
    }

    static String getADOSPassword() {
        String password = System.getenv('ADOS_PASSWORD')
        assert password
        return password
    }

    static String getADOSToken() {
        String token = System.getenv('ADOS_TOKEN')
        assert token
        return token
    }

    static String getADOSURL() {
        String url = System.getenv('ADOS_URL')
        assert url
        return url
    }

    static String getADOSCollectionName() {
        String collectionName = System.getenv('ADOS_COLLECTION')
        assert collectionName
        return collectionName
    }

    static String getADOSProjectName() {
        String projectName = System.getenv('ADOS_PROJECT_NAME')
        assert projectName
        return projectName
    }

    static String getADOSApiVersion() {
        String apiVersion = System.getenv('ADOS_API_VERSION')
        assert apiVersion
        return apiVersion
    }

    static TFSHelper getTFSHelper(String apiVersion = "1.0") {
        TFSHelper helper = new TFSHelper(getADOSURL(), getADOSUsername(), getADOSToken(), getADOSCollectionName(), getADOSProjectName())

        helper.setApiVersion(apiVersion)
        helper.setProjectName(getADOSProjectName())

        assert helper.isAuthenticated()
        return helper
    }

//    def redirectLogs(String parentProperty = '/myJob') {
//        def propertyLogName = parentProperty + '/debug_logs'
//        dsl """
//            setProperty(
//                propertyName: "/plugins/EC-TFS/project/ec_debug_logToProperty",
//                value: "$propertyLogName"
//            )
//        """
//        return propertyLogName
//    }
//
//    def redirectLogsToPipeline() {
//        def propertyName = '/myPipelineRuntime/debugLogs'
//        dsl """
//            setProperty(
//                propertyName: "/plugins/EC-TFS/project/ec_debug_logToProperty",
//                value: "$propertyName"
//            )
//        """
//        propertyName
//    }
//
//    def getJobLogs(def jobId) {
//        assert jobId
//        def logs
//        try {
//            logs = getJobProperty("/myJob/debug_logs", jobId)
//        } catch (Throwable e) {
//            logs = "Possible exception in logs; check job"
//        }
//        logs
//    }
//
//    def getPipelineLogs(flowRuntimeId) {
//        assert flowRuntimeId
//        getPipelineProperty('/myPipelineRuntime/debugLogs', flowRuntimeId)
//    }
//
//    def runProcedureDsl(dslString) {
//        redirectLogs()
//        assert dslString
//
//        def result = dsl(dslString)
//        assert result.jobId
//        waitUntil {
//            jobCompleted result.jobId
//        }
//        def logs = getJobLogs(result.jobId)
//        def outcome = jobStatus(result.jobId).outcome
//        logger.debug("DSL: $dslString")
//        logger.debug("Logs: $logs")
//        logger.debug("Outcome: $outcome")
//        [logs: logs, outcome: outcome, jobId: result.jobId]
//    }

    def getCurrentProcedureName(def jobId) {
        assert jobId
        def currentProcedureName
        def property = "/myJob/procedureName"
        try {
            currentProcedureName = getJobProperty(property, jobId)
            println("Current Procedure Name: " + currentProcedureName)
        } catch (Throwable e) {
            logger.debug("Can't retrieve Run Procedure Name from the property: '$property'; check job: " + jobId)
        }
        return currentProcedureName
    }

    def getJobUpperStepSummary(def jobId) {
        assert jobId
        def summary
        def currentProcedureName = getCurrentProcedureName(jobId)
        def property = "/myJob/jobSteps/$currentProcedureName/summary"
        println "Trying to get the summary for Procedure: $currentProcedureName, property: $property, jobId: $jobId"
        try {
            summary = getJobProperty(property, jobId)
        } catch (Throwable e) {
            logger.debug("Can't retrieve Upper Step Summary from the property: '$property'; check job: " + jobId)
        }
        return summary
    }

    def getStepSummary(def jobId, def stepName) {
        assert jobId
        def summary
        def property = "/myJob/jobSteps/$stepName/summary"
        println "Trying to get the summary for Procedure: checkConnection, property: $property, jobId: $jobId"
        try {
            summary = getJobProperty(property, jobId)
        } catch (Throwable e) {
            logger.debug("Can't retrieve Upper Step Summary from the property: '$property'; check job: " + jobId)
        }
        return summary
    }

    def getPipelineOutputParameters(def flowRuntimeId) {
        assert flowRuntimeId
        def prams = getPipelineProperty('/myPipelineRuntime/', flowRuntimeId)
    }

    def getJobOutputParameters(def jobId, def stepNumber) {
        assert jobId
        def outputParameters = []
        def stepId = getJobStepId(jobId, stepNumber)
        try {
            outputParameters = dsl """
            getOutputParameters(
                jobStepId: '$stepId'
                )
          """
        } catch (Throwable e) {
            logger.debug("Can't retrieve output parameters for job: " + jobId)
            e.printStackTrace()
        }

        def map = [:]
        for (i in outputParameters.outputParameter) {
            map[(String) i.outputParameterName] = i.value
        }
        return map
    }

    def createResource(def resName) {
        dsl """
            createResource(
                resourceName: '$resName',
                hostName: '127.0.0.1',
                port: '7800'
            )
        """
    }

    def conditionallyDeleteProject(String projectName) {
        if (System.getenv("LEAVE_TEST_PROJECTS")) {
            return
        }
        dsl "deleteProject(projectName: '$projectName')"
    }

    static boolean mapEquals(Map map1, Map map2){
        return map1 == map2
    }

}
