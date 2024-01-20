Request :: struct {
    #as socket      : MySocket;

    raw             : string; // entire raw http request
    body            : string; // pointer into raw
    path            : string; // pointer into raw

    content_length  : u32;
    method          : METHOD;
    websocket_key   : string;
    accept_encoding : string;

    params          : Table(string, string);
    query           : Table(string, string);
    headers         : Table(string, string);
    form_data       : Table(string, string);
    cookies         : Table(string, string);

    response_sent   : bool;
    err             : bool;

    #if OS == .LINUX {
        buffercursor  : u32;
        startofline   : u32;
    }
}
get_param :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.params, name);
    if !found return "";
    return val;
}
get_query :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.query, name);
    if !found return "";
    return val;
}
get_header :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.headers, name);
    if !found return "";
    return val;
}
get_formdata :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.form_data, name);
    if !found return "";
    return val;
}
get_cookie :: (request: *Request, name: string) -> string {
    val, found := table_find(*request.cookies, name);
    if !found return "";
    return val;
}
operator == :: inline (a: Request, b: Request) -> bool {return a.socket == b.socket; }

does_request_accept_encoding :: (request: *Request, encoding: string) -> bool {
  if !request.accept_encoding return false;
  for encoding: split(request.accept_encoding, ",") {
    if trim(encoding, " ") == encoding return true;
  }
  return false;
}

handle_request :: (request: *Request) {

    contains_prams :: (s: string) -> bool {
        return contains(s, ":");
    }

    is_path_match :: (a: string, b: string) -> bool {
        if !contains_prams(a) return a == b;

        parts_a := split(a, "/");
        parts_b := split(b, "/");
        if parts_a.count != parts_b.count return false;

        for parts_a {
            part_a := parts_a[it_index];
            part_b := parts_b[it_index];
            if !contains_prams(part_a) {
                if part_a != part_b return false;
            }
        }

        return true;
    }

    parse_query_params :: (query_str: string) -> Table(string, string) {
        query_params: Table(string, string);

        key_builder: String_Builder;
        init_string_builder(*key_builder);
        value_builder: String_Builder;
        init_string_builder(*value_builder);

        ParseState :: enum u8 {KEY; VALUE;}

        state := ParseState.KEY;

        for i : 0..query_str.count-1 {
            if query_str[i] == {
                case #char "&";
                if state == .KEY {
                    // we encountered a loose key without a value, so we just set it to "true", i.e. /page?flag&foo
                    table_add(*query_params, builder_to_string(*key_builder), "true");
                } else {
                    table_add(*query_params, builder_to_string(*key_builder), builder_to_string(*value_builder));
                }
                state = .KEY;
                case #char "=";
                state = .VALUE;
                case;
                char := ascii(query_str[i]);
                if state == .KEY {
                    print_to_builder(*key_builder, char);
                } else {
                    print_to_builder(*value_builder, char);
                }
            }
        }

        if state == .VALUE {
            key := builder_to_string(*key_builder);
            value := builder_to_string(*value_builder);

            if value.count > 0 {
                table_add(*query_params, key, value);
            } else {
                // we encountered a loose key without a value, so we just set it to "true", i.e. /page?flag&foo
                table_add(*query_params, key, "true");
            }
        }

        return query_params;
    }

    parse_path_query_params :: (path: string) -> string, Table(string, string) {
        path_parts := split(path, "?");
        path_str := path_parts[0];

        assert(path_parts.count > 0);

        if path_parts.count == 1 {
            // no query params
            empty_query_params: Table(string, string);
            return path_str, empty_query_params;
        }

        query_str := path_parts[1];

        if query_str.count == 0 {
            // no query params
            empty_query_params: Table(string, string);
            return path_str, empty_query_params;
        }

        query_params := parse_query_params(query_str);

        return path_str, query_params;
    }

    path_normal := normalize_path(request.path);

    path_normal, request.query = parse_path_query_params(path_normal);
    
    cookie_header := get_header(request, "Cookie");
    if cookie_header {
        for cookie_str : split(cookie_header, ";") {
            cookie_kv := split(cookie_str, "=");
            if cookie_kv.count < 2 {
                print("[ERROR] Invalid cookie header: %\n", cookie_header);
                break;
            }
            table_add(*request.cookies, trim(cookie_kv[0]), trim(cookie_kv[1]));
        }
    }

    content_type := get_header(request, "Content-Type");
    if content_type == "application/x-www-form-urlencoded" {
        decoded_body := url_decode(request.body);
        // print("form urlencoded: %\n", request.body);
        // print("decoded: %\n", decoded_body);
        request.form_data = parse_query_params(decoded_body);
    }

    if request.websocket_key {
        if table_find_pointer(*websocket_servers, path_normal) {
            websocket_handle_request(request);
        } else {
            // todo: received a websocket request for a path we're not listening to. maybe some kind of notification, send a proper decline response?
        }
    }

    // let the user's middleware handle the request!
    for middleware: middlewares {

        if request.response_sent then break; // once a middleware handles the request, we stop. this is first because webhook could've handled it already

        if middleware.method != .ANY && middleware.method != request.method then continue;
        // if middleware.path != "*" && middleware.path != request.path then continue;
        if middleware.path != "*" && !is_path_match(middleware.path, path_normal) then continue;

        table_reset(*request.params); // maybe this should happen somewhere else?
        middleware_contains_params := contains_prams(middleware.path);
        if middleware_contains_params {
            middleware_path_split := split(middleware.path, "/");
            request_path_split := split(path_normal, "/");
            for middleware_path_split {
                if !contains_prams(it) continue;
                param_name := middleware_path_split[it_index];
                param_name.data += 1;
                param_name.count -= 1;
                // array_add(request.params, request_path_split[it_index]);
                // request.params[param_name] = request_path_split[it_index];
                table_add(*request.params, param_name, request_path_split[it_index]);
                // request.params[param_name] = request_path_split[it_index];
            }
        }

        middleware.cb(request);
    }

    // if none of the middleware responded to this request, 404
    if !request.response_sent {
        if fallback_handler {
            fallback_handler(request);
        } else {
            send_html(request, tprint("<pre>Cannot % %</pre>", request.method, request.path), status_code=404);
        }
    }
}


METHOD :: enum u8 {ANY; GET; POST; PUT; DELETE;}
to_METHOD :: (str: string) -> METHOD {
  if str == {
    case "GET";     return .GET;
    case "POST";    return .POST;
    case "PUT";     return .PUT;
    case "DELETE";  return .DELETE;
    case;           return .ANY;
  }
}