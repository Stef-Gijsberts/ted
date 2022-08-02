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

pub fn main() anyerror!void {
    try raw_mode.enter();
    defer raw_mode.exit();

    const in = std.io.getStdIn();
    const out = std.io.getStdOut();

    var key: u8 = undefined;

    while (true) {
        // Clear screen
        _ = try out.write("\x1B[1J");
        
        // Read a character
        _ = try in.read(@as(*[1]u8, &key));

        // Close when ctrl+c is pressed
        if (key == 3) {
            break;
        }
    }
}
