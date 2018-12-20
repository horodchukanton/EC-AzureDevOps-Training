package com.electriccloud.plugin.spec.http;

import org.apache.commons.codec.binary.Base64;
import org.apache.http.HttpRequest;
import org.apache.http.auth.AUTH;
import org.apache.http.auth.Credentials;
import org.apache.http.auth.UsernamePasswordCredentials;
import org.apache.http.message.BufferedHeader;
import org.apache.http.util.CharArrayBuffer;
import org.apache.http.util.EncodingUtils;

public class HeaderCredentials extends BasicCredentials {

    private String username;
    private String password;

    public HeaderCredentials(String username, String password) {
        super(username, password);
        this.username = username;
        this.password = password;
    }

    @Override
    public void authenticate(HttpRequest req) {
        Credentials credentials = new UsernamePasswordCredentials(this.username, this.password);

        final StringBuilder tmp = new StringBuilder();
        tmp.append(credentials.getUserPrincipal().getName());
        tmp.append(":");
        tmp.append((credentials.getPassword() == null) ? "null" : credentials.getPassword());

        final byte[] base64password = Base64.encodeBase64(
                EncodingUtils.getBytes(tmp.toString(), "utf-8"), false);

        final CharArrayBuffer buffer = new CharArrayBuffer(32);

        buffer.append(AUTH.WWW_AUTH_RESP);

        buffer.append(": Basic ");
        buffer.append(base64password, 0, base64password.length);

        BufferedHeader header = new BufferedHeader(buffer);

        req.addHeader(header);
    }
}
