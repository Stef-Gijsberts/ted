const std = @import("std");
const os = std.os;
const linux = std.os.linux;

const Key = union(enum) {
    backspace,
    enter,
    char: u8,
    ctrl: u8,
};

const raw_mode = struct {
    var maybe_original: ?os.termios = null;

    fn enter() !void {
        // This code is based on the enableRawMode() function from Kilo, which
        // is written by Salvatore Sanfilippo aka antirez, licensed under the
        // BSD 2 clause license.
        //
        // The enableRawMode() function can be found on GitHub:
        // https://github.com/antirez/kilo/blob/69c3ce609d1e8df3956cba6db3d296a7cf3af3de/kilo.c#L218,

        const original = try os.tcgetattr(os.STDIN_FILENO);
        maybe_original = original;

        var raw = original;
        raw.iflag &= ~(linux.BRKINT | linux.ICRNL | linux.INPCK | linux.ISTRIP | linux.IXON);
        raw.oflag &= ~(linux.OPOST);
        raw.cflag |= (linux.CS8);
        raw.lflag &= ~(linux.ECHO | linux.ICANON | linux.IEXTEN | linux.ISIG);

        try os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, raw);
    }

    fn exit() void {
        if (maybe_original) |original| {
            os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, original) catch {};
        }
    }
};

fn getByte() !u8 {
    const in = std.io.getStdIn();

    var key: u8 = undefined;
    _ = try in.read(@as(*[1]u8, &key));

    return key;
}

fn getKey() !Key {
    const byte = try getByte();

    switch (byte) {
        '\r', '\n' => return Key.enter,
        127 => return Key.backspace,
        1...9, 11...12, 14...31 => return Key{ .ctrl = 'a' + byte - 1 },
        else => return Key{ .char = byte },
    }
}

const terminal = struct {
    const csi = "\x1B[";
    const clear_screen = csi ++ "2J";
    const cursor_goto_top_left = csi ++ "1;1H";
    const cursor_save = csi ++ "s";
    const cursor_restore = csi ++ "u";
};

fn render(bytes: *const std.ArrayList(u8), cursor: usize) !void {
    const out = std.io.getStdOut();

    _ = try out.write(terminal.clear_screen);
    _ = try out.write(terminal.cursor_goto_top_left);
    _ = try out.write(terminal.cursor_save);

    // Write the buffer
    for (bytes.items) |byte, index| {
        if (byte == '\n') {
            // Replace any '\n' by a '\r\n'
            _ = try out.write("\r\n");
        } else {
            _ = try out.write(&[_]u8{byte});
        }

        if (index + 1 == cursor) {
            _ = try out.write(terminal.cursor_save);
        }
    }

    _ = try out.write(terminal.cursor_restore);
}

pub fn main() anyerror!void {
    try raw_mode.enter();
    defer raw_mode.exit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var bytes = std.ArrayList(u8).init(gpa.allocator());
    defer bytes.deinit();

    var cursor: usize = 0;

    while (true) {
        try render(&bytes, cursor);

        const key = try getKey();

        switch (key) {
            Key.ctrl => |char| switch (char) {
                // break on ctrl+c
                'c' => break,
                'b' => if (cursor > 0) {
                    cursor -= 1;
                },
                'f' => if (cursor < bytes.items.len) {
                    cursor += 1;
                },
                else => {},
            },
            Key.enter => {
                try bytes.insert(cursor, '\n');
                cursor += 1;
            },
            Key.backspace => {
                if (cursor > 0) {
                    _ = bytes.orderedRemove(cursor - 1);
                    cursor -= 1;
                }
            },
            Key.char => |char| {
                try bytes.insert(cursor, char);
                cursor += 1;
            },
        }
    }
}
