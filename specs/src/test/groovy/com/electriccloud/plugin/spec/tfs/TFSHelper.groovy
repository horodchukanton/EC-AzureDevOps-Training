package com.electriccloud.plugin.spec.tfs


import com.electriccloud.plugin.spec.http.HeaderCredentials
import com.electriccloud.plugin.spec.http.ICredentials
import com.electriccloud.plugin.spec.http.RestClient
import com.electriccloud.plugin.spec.http.RestException
import net.sf.json.JSON
import org.apache.http.client.methods.HttpPost
import org.apache.http.impl.client.DefaultHttpClient


class TFSHelper {
    final static String METHOD_GET = 'GET'
    final static String METHOD_POST = 'POST'
    final static String METHOD_PUT = 'PUT'
    final static String METHOD_PATCH = 'PATCH'
    final static String METHOD_DELETE = 'DELETE'

    String url
    String login
    String password

    String collectionName
    String apiVersion = '1.0'
    String projectName
    String projectPrefix

    RestClient client

    TFSHelper(String url, String login, String password, String collectionName, String projectName = "DefaultCollection") {
        assert url
        assert login
        assert password
        assert collectionName

        this.collectionName = collectionName
        this.projectName = projectName

        this.url = url

        this.login = login
        this.password = password

        // Credentials
        ICredentials credentials = new HeaderCredentials(login, password)

        // Instantiate client
        DefaultHttpClient httpclient = new DefaultHttpClient()
        client = new RestClient(httpclient, credentials, URI.create(this.url))

        // TODO: check auth
    }

    void setApiVersion(String apiVersion){
        this.apiVersion = apiVersion
    }

    void setProjectName(String projectName){
        this.projectName = projectName
        this.projectPrefix = '/' + this.collectionName + '/' + this.projectName
    }

    JSON getWorkItemById(def id){
        assert id
        String path = this.collectionName + '/_apis/wit/workitems/' + id
        return request(METHOD_GET, path)
    }

    /**
     * Creates a work Item. Map keys should be the same as CreateWorkItems procedure parameters
     *
     * @param workItemParams
     * @return
     */
    JSON createWorkItem(String workItemType, Map workItemParams){
        String path = [this.collectionName, this.projectName, '_apis/wit/workitems', "\$${workItemType}"].join("/")

        // Transforming parameter map to TFS expected JSON payload format
        def tfsWorkItems = new WorkItemFields(workItemParams)
        JSON payload = tfsWorkItems.getAsJSONPayload()

        return postWithContentType(
            path,
            [ 'api-version' : getApiVersion() ],
            payload,
            "application/json-patch+json"
        )
    }

    JSON deleteWorkItem(def workItemId){
        String path = [this.collectionName, '/_apis/wit/workitems', workItemId].join('/')
        return request(METHOD_DELETE, path)
    }

    boolean isAuthenticated(){
        return true
    }

    JSON request(String method, String path, Map parameters = [:], JSON payload = null){
        assert method
        assert path

        // Adding api-version to parameters
        parameters['api-version'] = this.apiVersion

        if (!path =~ /^\//){
            path = '/' + path
        }

        def url_with_params = this.client.buildURI(path, parameters)

        if (payload && ( method == METHOD_PUT || method == METHOD_POST)){
            throw new RuntimeException("Payload is implemented only for PUT and POST methods")
        }

        JSON result = null

        try {
            // Adding parameters to URI
            switch (method.toUpperCase()) {
                case METHOD_GET:
                    result = this.client.get(url_with_params)
                    break
                case METHOD_POST:
                    result = this.client.post(url_with_params, payload)
                    break
                case METHOD_PUT:
                    result = this.client.put(url_with_params, payload)
                    break
                case METHOD_PATCH:
                    result = this.client.patch(url_with_params)
                    break
                case METHOD_DELETE:
                    result = this.client.delete(url_with_params)
                    break
            }
        } catch (RestException e){
            println "Error happened for the request" + e.getHttpStatusCode()
            println e.getMessage()
        }

        assert result
        return result
    }

    JSON postWithContentType(String path, Map queryParameters = [:], JSON payload, String contentType){
        assert queryParameters['api-version']
        URI uri = this.client.buildURI(path, queryParameters)

        HttpPost request = new HttpPost(uri)

        JSON result = null
        try {
            result = this.client.request(request, payload.toString(), contentType)
        } catch (RestException e){
            println "Error happened for the request" + e.getHttpStatusCode()
            println e.getMessage()
        }
        assert result
        return result
    }
}
