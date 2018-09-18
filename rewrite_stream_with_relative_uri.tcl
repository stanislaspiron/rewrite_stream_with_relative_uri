when RULE_INIT {
    unset static::rewrite_table
    array set static::rewrite_table {
        "https://www.company.com"   "http://srv-internal.company.local"
        "https://www2.company.com"   "http://srv-internal2.company.local"
    }
    set static::rewrite_table_map [list]
    set static::rewrite_table_stream [list]
    foreach item [array names static::rewrite_table] {
        lappend static::rewrite_table_map $static::rewrite_table($item)/ $item/ $static::rewrite_table($item) $item/
        lappend static::rewrite_table_stream "@$static::rewrite_table($item)/@$item/@"
    }
    log local0. $static::rewrite_table_map
    log local0. $static::rewrite_table_stream
    # create stream commands in variables to run them only id stream profile is enabled
    set static::stream_disable "STREAM::disable"
    set static::stream_enable "STREAM::enable"
    # change stream expression to convert current site response to relative URI.
    set static::stream_expression "STREAM::expression \[string map \"\$req_proto://\$req_host/ /\" \$static::rewrite_table_stream\]"
}

when CLIENT_ACCEPTED {
    # set default protocol to http. change it to https if clientssl profile is assigned to the VS.
    if { [PROFILE::exists clientssl] == 1} {
        set req_proto "https"
    } else {
        set req_proto "http"
    }
    set stream_profile_enabled [PROFILE::exists stream]
}

when HTTP_REQUEST {
    # Capture request hostname
    set req_host [HTTP::host]
    if {$stream_profile_enabled} {
        # Disable the stream filter for all requests
        eval $static::stream_disable

        # LTM does not uncompress response content, so if the webserver has compression enabled
        # we must prevent the server from send us a compressed response by changing the request
        # header that indicates client support for compression (on our LTM client-side we can re-
        # apply compression before the response goes across the Internet)
        HTTP::header remove "Accept-Encoding"
    }
}

when HTTP_RESPONSE {
    if { [HTTP::status]  matches "30?"} {
        # This is a 302 redirect with a absolute Location URI
        HTTP::header replace Location [string map [string map "$req_proto://$req_host/ /" $static::rewrite_table_map] [HTTP::header Location]]
    } elseif {[HTTP::header value Content-Type] starts_with "text"} {
        # Apply stream expression stored in RULE_INIT event
        if {$stream_profile_enabled} {
            eval $static::stream_expression

            # Enable the stream filter for this response only
            eval $static::stream_enable
        }
    }
}