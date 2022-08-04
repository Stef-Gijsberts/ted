const std = @import("std");
const os = std.os;
const linux = std.os.linux;

const c = @cImport({
    @cInclude("termios.h");
});

const Key = union(enum) {
    backspace,
    enter,
    escape,
    up,
    left,
    down,
    right,
    char: u8,
    ctrl: u8,
};

const Command = union(enum) {
    cursor_move_forwards,
    cursor_move_backwards,
    cursor_goto_line_start,
    cursor_goto_line_end,
    insert_before_cursor: u8,
    delete_before_cursor,
    exit,
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

        // The minimum number of bytes of input before read() can return
        raw.cc[c.VMIN] = 0;

        // The maximum amount of time in deciseconds (100ms) to wait before
        // read() returns.
        raw.cc[c.VTIME] = 1;

        try os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, raw);
    }

    fn exit() void {
        if (maybe_original) |original| {
            os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, original) catch {};
        }
    }
};

fn pollByte() !?u8 {
    const in = std.io.getStdIn();

    var key: u8 = undefined;

    const num_bytes_read = try in.read(@as(*[1]u8, &key));

    if (num_bytes_read == 0) {
        return null;
    }

    return key;
}

fn getByte() !u8 {
    while (true) {
        const maybe_byte = try pollByte();

        if (maybe_byte) |byte| {
            return byte;
        }
    }
}

fn getKey() !Key {
    const byte = try getByte();

    switch (byte) {
        '\r', '\n' => return Key.enter,
        127 => return Key.backspace,
        1...9, 11...12, 14...26, 28...31 => return Key{ .ctrl = 'a' + byte - 1 },
        '\x1B' => {
            const byte2 = (try pollByte()) orelse return Key.escape;
            const byte3 = (try pollByte()) orelse return Key.escape;

            if (byte2 == '[') {
                switch (byte3) {
                    'A' => return Key.up,
                    'B' => return Key.down,
                    'C' => return Key.right,
                    'D' => return Key.left,
                    else => return Key.escape,
                }
            }

            return Key.escape;
        },
        else => return Key{ .char = byte },
    }
}

fn getCommand() !Command {
    while (true) {
        const key = try getKey();

        switch (key) {
            Key.enter => return Command{ .insert_before_cursor = '\n' },
            Key.left => return Command.cursor_move_backwards,
            Key.right => return Command.cursor_move_forwards,
            Key.ctrl => |char| switch (char) {
                'c' => return Command.exit,
                'f' => return Command.cursor_move_forwards,
                'b' => return Command.cursor_move_backwards,
                'a' => return Command.cursor_goto_line_start,
                'e' => return Command.cursor_goto_line_end,
                else => {},
            },
            Key.backspace => return Command.delete_before_cursor,
            Key.char => |char| return Command{ .insert_before_cursor = char },
            Key.escape, Key.up, Key.down => {},
        }
    }
}

const terminal = struct {
    const csi = "\x1B[";
    const clear_screen = csi ++ "2J";
    const cursor_goto_top_left = csi ++ "1;1H";
    const cursor_save = csi ++ "s";
    const cursor_restore = csi ++ "u";
};

fn render(sequence: *const Sequence, cursor: isize) !void {
    const out = std.io.getStdOut().writer();

    try out.print("{s}{s}{s}", .{ terminal.clear_screen, terminal.cursor_goto_top_left, terminal.cursor_save });

    // Write the buffer
    for (sequence.bytes.items) |byte, index| {
        if (byte == '\n') {
            // Replace any '\n' by a '\r\n'
            try out.writeAll("\r\n");
        } else {
            try out.writeAll(&[_]u8{byte});
        }

        if (index + 1 == cursor) {
            try out.writeAll(terminal.cursor_save);
        }
    }

    try out.writeAll(terminal.cursor_restore);
}

const Sequence = struct {
    const Self = @This();
    bytes: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .bytes = std.ArrayList(u8).init(allocator),
        };
    }

    fn deinit(self: Self) void {
        self.bytes.deinit();
    }

    fn len(self: *const Self) isize {
        return @intCast(isize, self.bytes.items.len);
    }

    fn get(self: *const Self, pos: isize) ?u8 {
        if (pos < 0 or pos >= self.bytes.items.len) {
            return null;
        }

        return self.bytes.items[@intCast(usize, pos)];
    }

    fn insert(self: *Self, pos: isize, byte: u8) !void {
        if (pos < 0 or pos > self.bytes.items.len) {
            return error.position_out_of_range;
        }

        try self.bytes.insert(@intCast(usize, pos), byte);
    }

    fn remove(self: *Self, pos: isize) !void {
        if (pos < 0 or pos > self.bytes.items.len) {
            return error.position_out_of_range;
        }

        _ = self.bytes.orderedRemove(@intCast(usize, pos));
    }
};

pub fn main() anyerror!void {
    try raw_mode.enter();
    defer raw_mode.exit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var sequence = Sequence.init(gpa.allocator());
    defer sequence.deinit();

    var cursor: isize = 0;

    while (true) {
        try render(&sequence, cursor);

        const command = try getCommand();

        switch (command) {
            Command.cursor_move_backwards => {
                if (cursor > 0) {
                    cursor -= 1;
                }
            },
            Command.cursor_move_forwards => {
                if (cursor < sequence.len()) {
                    cursor += 1;
                }
            },
            Command.cursor_goto_line_start => {
                while ((sequence.get(cursor - 1) orelse '\n') != '\n') {
                    cursor -= 1;
                }
            },
            Command.cursor_goto_line_end => {
                while ((sequence.get(cursor) orelse '\n') != '\n') {
                    cursor += 1;
                }
            },
            Command.insert_before_cursor => |char| {
                try sequence.insert(cursor, char);
                cursor += 1;
            },
            Command.delete_before_cursor => {
                if (cursor > 0) {
                    try sequence.remove(cursor - 1);
                    cursor -= 1;
                }
            },
            Command.exit => break,
        }
    }
}
