// adapted from https://stackoverflow.com/a/51981309

ASCII_HEX_4BIT :: u8.[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 0, 0, 0, 0, 10, 11, 12, 13, 14, 15];

to_upper :: (c: u8) -> u8 {
    if ((c >= #char "a") && (c <= #char "z")) return c ^ 0x20;
    return c;
}

url_decode :: (str: string) -> string {
    i, j := 0;
    c, d, url_hex: u8;
    d = str[0];

    decoded := alloc_string(str.count + 1,, temp);

    while (i < str.count) && (d != 0) {
        c = str[i];
        d = 0;

        if (c == #char "%") {
            i += 1;
            url_hex = to_upper(str[i]);
            if (((url_hex >= #char "0") && (url_hex <= #char "9")) || ((url_hex >= #char "A") && (url_hex <= #char "F"))) {
                d = ASCII_HEX_4BIT[url_hex - 48] << 4;

                i += 1;
                url_hex = to_upper(str[i]);
                if (((url_hex >= #char "0") && (url_hex <= #char "9")) || ((url_hex >= #char "A") && (url_hex <= #char "F"))) {
                    d |= ASCII_HEX_4BIT[url_hex - 48];
                } else {
                    d = 0;
                }
            }
        }
        else if (c == #char "+") {
            d = #char " ";
        }
        else {
            d = c;
        }

        decoded[j] = d;
        j += 1;
        i += 1;
    }


    decoded[j] = 0;
    return decoded;
}