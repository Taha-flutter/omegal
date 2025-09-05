class CP {
  // ANSI color codes
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';

  // Method to print in red
  static void red(String message) {
    print('$_red$message$_reset');
  }

  // Method to print in green
  static void green(String message) {
    print('$_green$message$_reset');
  }

  // Method to print in yellow
  static void yellow(String message) {
    print('$_yellow$message$_reset');
  }

  // Method to print in blue
  static void blue(String message) {
    print('$_blue$message$_reset');
  }

  // Method to print in magenta
  static void magenta(String message) {
    print('$_magenta$message$_reset');
  }

  // Method to print in cyan
  static void cyan(String message) {
    print('$_cyan$message$_reset');
  }

  // Method to print in white (default color)
  static void white(String message) {
    print('$_white$message$_reset');
  }
}
