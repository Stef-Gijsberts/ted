const std = @import("std");
const os = std.os;
const linux = std.os.linux;

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

fn render(bytes: *const std.ArrayList(u8)) !void {
    const out = std.io.getStdOut();

    // clear screen
    _ = try out.write("\x1B[1J");

    // Move the cursor to the top left
    _ = try out.write("\x1B[1;1H");

    // Write the buffer
    _ = try out.write(bytes.items);
}

pub fn main() anyerror!void {
    try raw_mode.enter();
    defer raw_mode.exit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var bytes = std.ArrayList(u8).init(gpa.allocator());
    defer bytes.deinit();

    while (true) {
        try render(&bytes);

        const key = try getByte();

        // Close when ctrl+c is pressed
        if (key == 3) {
            break;
        }

        try bytes.append(key);
    }
}
