/*
 *  This code was borrowed from JIRA client (net.rcarz.jiraclient package)
 *
 * */

package com.electriccloud.plugin.spec.http;

import org.apache.http.HttpRequest;

public interface ICredentials {

    void initialize(RestClient client) throws RestException;
    /**
     * Sets the Authorization header for the given request.
     *
     * @param req HTTP request to authenticate
     */
    void authenticate(HttpRequest req);

    /**
     * Gets the logon name representing these credentials.
     *
     * @return logon name as a string
     */
    String getLogonName();

    void logout(RestClient client) throws RestException;
}