ENABLE_HTTPS :: false;

#load "files.jai";
#load "parse.jai";
#load "request.jai";
#load "response.jai";
#load "urlencode.jai";
#load "websocket.jai";

#if OS == .WINDOWS #load "windows.jai";
#if OS == .LINUX   #load "linux.jai";

// the main entry point is http_listen, which is defined in linux.jai and windows.jai

// todo: this method of looping through middlewares is slow @perf
middlewares: [..]Middleware;
fallback_handler: (*Request)->();

Middleware :: struct {
    method: METHOD;
    path: string;
    cb: (*Request)->();
}

get  :: (path: string, cb: (*Request)->()) {array_add(*middlewares, .{method=.GET , cb=cb, path=normalize_path(path)}); }
post :: (path: string, cb: (*Request)->()) {array_add(*middlewares, .{method=.POST, cb=cb, path=normalize_path(path)}); }
any  :: (path: string, cb: (*Request)->()) {array_add(*middlewares, .{method=.ANY , cb=cb, path=normalize_path(path)}); }

fallback :: (cb: (*Request)->()) {fallback_handler = cb; }


normalize_path :: (path: string) -> string { return trim(path, "/"); }

hex_char_to_int :: (char: u8) -> u8 {
    if char >= #char "a" return (char - #char "a" + 0xA);
    if char >= #char "A" return (char - #char "A" + 0xA);
    if char >= #char "0" return (char - #char "0");
    return 1;
}
hex_chars_to_byte :: (chars: string) -> u8 {
    assert(chars.count == 2);
    return hex_char_to_int(chars[0]) * 16 + hex_char_to_int(chars[1]);
}




mysocket_read :: (socket: Socket, buffer: *u8, bufferlen: s32) -> s64 {

    #if OS == .LINUX && ENABLE_HTTPS {
        if ssl_is_socket_ssl(socket) { // perf hash table lookup
            return ssl_read(socket, buffer, xx bufferlen);
        }
    }

    return recv(socket, buffer, xx bufferlen, 0);
}

mysocket_write :: (socket: Socket, buffer: string) -> s64 {

    #if OS == .LINUX && ENABLE_HTTPS {
        if ssl_is_socket_ssl(socket) { // perf hash table lookup
            return ssl_write(socket, buffer.data, xx buffer.count);
        }
    }
    
    // print("[mysocket_write] send buffer: %\n", buffer.count);

    total_bytes_sent := 0;
    while total_bytes_sent < buffer.count {
        bytes_sent := send(socket, buffer.data + total_bytes_sent, xx buffer.count, 0);
        
        // @TODO handle errors on windows
        #if OS != .WINDOWS {
            if bytes_sent == -1 {
                err := errno();
                if err == {
                    case EWOULDBLOCK;
                    // the socket is non-blocking, keep retrying
                    continue;
                    
                    case;
                    // some other error occurred
                    print("[mysocket_write] failed due to errno %\n", err);
                    return -1;
                }
            }
        }

        total_bytes_sent += bytes_sent;
        // print("[mysocket_write] sent % bytes so far...\n", total_bytes_sent);
    }
    // print("[mysocket_write] completed, sent total of % bytes.\n", total_bytes_sent);
    return total_bytes_sent;
}


#import "String";
#if OS != .WINDOWS #import "POSIX";


#scope_file

ascii :: (num: u8) -> string #expand {
    // must be a macro or *num gets invalidated after return
    str : string = ---;
    str.count = 1;
    str.data  = *num;
    return str;
}