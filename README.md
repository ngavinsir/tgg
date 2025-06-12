# tgg

![demo](https://github.com/ngavinsir/tgg/blob/014069f93883b3415b2f42f9d1b532929f77c6d7/demo/1.gif)

typing practice in your terminal

- Does not use terminfo. Use some escape codes from VT100.
- Dependency-free, tgg only depends on zig standard library and the compiler.
- Zero runtime allocations

calculation:

- wpm: total number of correct characters (including spaces) divided by 5, then divided by elapsed minutes
- acc: total number of correct characters (including spaces) divided by total number of characters
