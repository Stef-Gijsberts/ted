const std = @import("std");
const os = std.os;
const linux = std.os.linux;

pub fn main() anyerror!void {
    // based on the enableRawMode function from Kilo, which is written by
    // Salvatore Sanfilippo aka antirez, licensed under the BSD 2 clause
    // license.
    // https://github.com/antirez/kilo/blob/69c3ce609d1e8df3956cba6db3d296a7cf3af3de/kilo.c#L218,
    const old = try os.tcgetattr(os.STDIN_FILENO);
    var raw = old;
    raw.iflag &= ~(linux.BRKINT | linux.ICRNL | linux.INPCK | linux.ISTRIP | linux.IXON);
    raw.oflag &= ~(linux.OPOST);
    raw.cflag |= (linux.CS8);
    raw.lflag &= (linux.ECHO | linux.ICANON | linux.IEXTEN | linux.ISIG);

    try os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, raw);
    defer os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, old) catch {};
}
