package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import spock.lang.*

class UploadWorkItemAttachment extends PluginTestHelper {

    // !!! Note about filePath (uploading from a file)
    // TFS limit for upload is about 4MB (at least for our TFS 2017 server)

    // !!! Note about fileContent (uploading from a fileContent parameter)
    // Value length is limited at 65535 characters ( 64KB )

    static String procedureName = "UploadWorkItemAttachment"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName

    @Shared
    def workItemId,
        uploadType,
        fileName

    @Shared
    def resultPropertySheet = '/myJob/uploadAttachment'
    @Shared
    def resultFormat = 'propertySheet'

    // Optional
    @Shared
    def comment

    @Shared
    String filePath

    @Shared
    String fileContent

    /// Specs parameters
    @Shared
    def caseId,
        expectedSummary,
        expectedOutcome

    @Shared
    String sourceType

    static oneKbChunk = "kZ6WGSC5aYRmRq3vWxAvkjkPQrHyHdkdqsPIIsCBswspKc3kjV71IycsqLLYe8MQE0QUe6pOCzdzfepFKgqZg0OYtSZsWLWgwSHMBAAvhnV8pduaY08W2nD6C4KwsBmwCIrGpNYuNpqpSZcepr9KIBUIHePXcg4QCjt4BsdcVMSyCiibdntW5ierxTafoKskwLbyrzuqFY0HhealmSzLRDiBjn3lae4dIMuVrdGRmcT91VAx3BfePMr31SoFnZ21morhSzZ8EVMIydDXRI4Uc0tfer3WtrP9dDX8Rtz6czL6fLWKEzsEjhCOKPsbQQsUxZ31Wg5wYoWij9OlaBQn3O177U755Qtc4szIXxP2MaHx8UiRzztTkbyHUvyXzuwfnyXklirVhCF72e1qfiIC4ngaoowuCevYN3UclQrhQmsOW648abM9xYIM9mfepbJWEiLNJIXhQg6gIzJUzTqgvHuwBSPcIIwgDo9FUprr4qzuzpwpwKSDGA0Duqaou0Ix8FL7LUZxH81KdLIubJlaUND6osrqZ3vJWzY1v1qjaui6akx17YI66XpzIg63FZtdPdpp4oR1JrVlfZfmc6WWTZcdS4Fx1FHKXVHhCLeFSqexIUqXdhMhE92YK9t9QEt2vycmJPS0NGlDmij1basVlRy1HJduoc9flvRpMMpYROMjzqQqrOQMpHSu2ZPbGpkhdGuby4e9YIQ5EAIyuAgejnYklwNOZdPR2bO9j4RK9QIwvctcXie7Z1oMqRAQtAdHOsa1SbRcP3f3EemxkJIBqrPrbMLqYY4nKq44rX3Pp7wZd9W7dkaNCmfMB8xmGbotkqn01HZthssQLRboRGlEYjHlIPVlEFP7vEjMmj0zembIHIngTaqKk5Mwo0TPVlX2hcuxpkOpgYsjKu78Gu1gCGDJFUItfyAJkP096TFVLICUbhjPpvNDWpznJSA8I4lmYgdixulB0du1jIyhppd0CMuVvNef9iZSFGEAdqIktuhb04APPKVVkB25QTi6lNGL"

    def doSetupSpec() {
        createConfiguration(configName)

        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]
        dslFile 'dsl/writeRandomFile.dsl', [
            projectName : projectName,
            resourceName: getResourceName()
        ]


        tfsClient = getClient()
        assert tfsClient
    }

    def doCleanupSpec() {
        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    @Unroll
    def '#caseId. Sanity. Upload Type: "#uploadType", ContentSource: "#sourceType"'() {
        given:

        fileName = (String) procedureName + caseId + '.txt'

        if (sourceType == 'content') {
            fileContent = generateContentWithSize(fileSizeKB)
            filePath = ''
        }
        else {
            println("Writing new file with size ${fileSizeKB} KB")
            filePath = generateFile(fileName, fileSizeKB)
            fileContent = ''
            println("File created at $filePath")
        }

        def workItem = tfsClient.createWorkItem('Feature', [
            title      : randomize(procedureName),
            description: "Delete me"
        ])

        workItemId = workItem.id

        Map procedureParams = [
            config             : config,
            workItemId         : workItemId,
            comment            : comment,
            filename           : fileName,
            uploadType         : uploadType,
            filePath           : filePath,
            fileContent        : fileContent,
            resultFormat       : resultFormat,
            resultPropertySheet: resultPropertySheet
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        cleanup:
        if (workItemId){
            tfsClient.deleteWorkItem(workItemId)
        }

        where:
        caseId     | uploadType | sourceType | fileSizeKB
        'CHNGME_1' | 'simple'   | 'content'  | 10
        'CHNGME_2' | 'simple'   | 'file'     | 10

        // This one (CHNGME_3) should switch to simple
        'CHNGME_3' | 'chunked'  | 'content'  | 10
    }

    @Unroll
    @IgnoreIf({ System.getenv("IS_PROXY_AVAILABLE") == '1' && System.getenv("ADOS_AUTH_NTLM") == 'true'})
    def '#caseId. Sanity. Upload Type: "chunked", ContentSource: "#sourceType"'() {
        given:

        fileName = (String) procedureName + caseId + '.txt'
        println("Writing new file with size ${fileSizeKB} KB")

        filePath = generateFile(fileName, fileSizeKB)
        fileContent = ''
        println("File created at $filePath")

        def workItem = tfsClient.createWorkItem('Feature', [
            title      : randomize(procedureName),
            description: "Delete me"
        ])

        workItemId = workItem.id

        Map procedureParams = [
            config             : config,
            workItemId         : workItemId,
            comment            : comment,
            filename           : fileName,
            uploadType         : uploadType,
            filePath           : filePath,
            fileContent        : fileContent,
            resultFormat       : resultFormat,
            resultPropertySheet: resultPropertySheet
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        cleanup:
        if (workItemId){
            tfsClient.deleteWorkItem(workItemId)
        }

        where:
        caseId     | uploadType | sourceType | fileSizeKB
        'CHNGME_4' | 'chunked'  | 'file'     | 4 * 1024
    }

    def generateFile(String fileName, int sizeInKB) {

        String tempDir = '/tmp'
        if (System.getenv("IS_WINDOWS") == 'true') {
            tempDir = 'C:\\temp'
        }

        def path = catPath(tempDir, fileName)

        writeRandomFile(path, sizeInKB)

        return path
    }

    String generateContentWithSize(int sizeInKB){
        String content = ''
        for (def i = 0; i < sizeInKB; i++) {
            content += oneKbChunk
        }
        return content
    }

    def writeRandomFile(String filePath, int size) {

        def result = runProcedureDsl((String) """
           runProcedure(
                projectName : '${projectName}',
                procedureName: 'WriteRandomFile',
                actualParameter: [
                        'filepath': '''$filePath''',
                        'sizeKB': '''$size'''
                ]
           )
           """)

        logger.debug("Write to file logs: " + result.logs)

        assert result.outcome == 'success'
    }

    def catPath(String dir, String file) {
        if (System.getenv("IS_WINDOWS")) {
            return dir + '\\\\' + file
        } else {
            return dir + '/' + file
        }
    }

}
