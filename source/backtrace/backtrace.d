module backtrace.backtrace;

version(linux) {
  import core.sys.linux.execinfo;
  extern (C) void* thread_stackBottom();
} else {
  static assert(0, "backtrace only works in a Linux environment, the advanced backtrace won't be attached.");
}

private enum maxBacktraceSize = 32;
private alias TraceHandler = Throwable.TraceInfo function(void* ptr);

struct Trace {
  string file;
  uint line;
}

struct Symbol {
  string line;

  string demangled() {
    import std.demangle;
    import std.algorithm, std.range;
    import std.conv : to;
    dchar[] symbolWith0x = line.retro().find(")").dropOne().until("(").array().retro().array();
    if (symbolWith0x.length == 0) return "";
    else return demangle(symbolWith0x.until("+").to!string());
  }
}

struct PrintOptions {
  uint detailedForN = 2;
  bool colored = false;
  uint numberOfLinesBefore = 3;
  uint numberOfLinesAfter = 3;
}

import std.stdio;

version(DigitalMars) {

  void*[] getBacktrace() {
    void*[maxBacktraceSize] buffer;

    static void** getBasePtr() {
      version(D_InlineAsm_X86) {
        asm { naked; mov EAX, EBP; ret; }
      } else version(D_InlineAsm_X86_64) {
        asm { naked; mov RAX, RBP; ret; }
      } else return null;
    }

    auto stackTop = getBasePtr();
    auto stackBottom = cast(void**) thread_stackBottom();
    void* dummy;
    uint traceSize = 0;

    if (stackTop && &dummy < stackTop && stackTop < stackBottom) {
      auto stackPtr = stackTop;

      for (traceSize = 0; stackTop <= stackPtr && stackPtr < stackBottom && traceSize < buffer.length; ) {
        buffer[traceSize++] = *(stackPtr + 1);
        stackPtr = cast(void**) *stackPtr;
      }
    }

    return buffer[0 .. traceSize].dup;
  }

} else {

  void*[] getBacktrace() {
    void*[maxBacktraceSize] buffer;
    auto size = backtrace(buffer.ptr, buffer.length);
    return buffer[0 .. size].dup;
  }

}

Symbol[] getBacktraceSymbols(const(void*[]) backtrace) {
  import core.stdc.stdlib : free;
  import std.conv : to;

  Symbol[] symbols = new Symbol[backtrace.length];
  char** c_symbols = backtrace_symbols(backtrace.ptr, cast(int) backtrace.length);
  foreach (i; 0 .. backtrace.length) {
    symbols[i] = Symbol(c_symbols[i].to!string());
  }
  free(c_symbols);

  return symbols;
}

Trace[] getLineTrace(const(void*[]) backtrace) {
  import std.conv : to;
  import std.string : chomp;
  import std.algorithm, std.range;
  import std.process;

  auto addr2line = pipeProcess(["addr2line", "-e" ~ exePath()], Redirect.stdin | Redirect.stdout);
  scope(exit) addr2line.pid.wait();

  Trace[] trace = new Trace[backtrace.length];
  // foreach_reverse is used due to some weird behaviour of addr2line
  // some addresses resolve differently if resolved after some other addresses
  foreach_reverse (i, bt; backtrace) {
    addr2line.stdin.writefln("0x%X", bt);
    addr2line.stdin.flush();
    dstring reply = addr2line.stdout.readln!dstring().chomp();
    with (trace[i]) {
      auto split = reply.retro().findSplit(":");
      if (split[0].equal("?")) line = 0;
      else line = split[0].retro().to!uint;
      file = split[2].retro().to!string;
    }
  }

  executeShell("kill -INT " ~ addr2line.pid.processID.to!string);
  return trace;
}

private string exePath() {
  import std.file : readLink;
  import std.path : absolutePath;
  string link = readLink("/proc/self/exe");
  string path = absolutePath(link, "/proc/self/");
  return path;
}

void printPrettyTrace(File output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1) {
  void*[] bt = getBacktrace();
  printPrettyTrace(bt, output, options, framesToSkip);
}

private void printPrettyTrace(const(void*[]) bt, File output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1) {
  import std.algorithm : max;
  import std.range;

  Symbol[] symbols = getBacktraceSymbols(bt);
  Trace[] trace = getLineTrace(bt);

  enum Color : char {
    black = '0',
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white
  }

  string forecolor(Color color) {
    if (!options.colored) return "";
    else return "\u001B[3" ~ color ~ "m";
  }

  string backcolor(Color color) {
    if (!options.colored) return "";
    else return "\u001B[4" ~ color ~ "m";
  }

  string reset() {
    if (!options.colored) return "";
    else return "\u001B[0m";
  }

  output.writeln("Stack trace:");

  foreach(i, t; trace.drop(framesToSkip)) {
    auto symbol = symbols[framesToSkip + i].demangled;
    output.writeln("#", i + 1, ": ", forecolor(Color.red), t.file, reset(), " line ", forecolor(Color.yellow), "(", t.line, ")", reset(), symbol.length == 0 ? "" : " in ", forecolor(Color.green), symbol, reset());

    if (i < options.detailedForN) {
      uint startingLine = max(t.line - options.numberOfLinesBefore - 1, 0);
      uint endingLine = t.line + options.numberOfLinesAfter;

      if (t.file == "??") continue;

      File code;
      try {
        code = File(t.file, "r");
      } catch (Exception ex) {
        continue;
      }

      auto lines = code.byLine();

      lines.drop(startingLine);
      auto lineNumber = startingLine + 1;
      output.writeln();
      foreach (line; lines.take(endingLine - startingLine)) {
        output.writeln(forecolor(t.line == lineNumber ? Color.yellow : Color.cyan), t.line == lineNumber ? ">" : " ", "(", lineNumber , ") ", forecolor(t.line == lineNumber ? Color.yellow : Color.blue), line);
        lineNumber++;
      }
      output.writeln(reset());

    }
  }
}

private class BTTraceHandler : Throwable.TraceInfo {
  void*[] backtrace;
  PrintOptions options;
  File output;
  uint framesToSkip;

  this(File file, PrintOptions options, uint framesToSkip) {
    this.options = options;
    this.output = file;
    this.framesToSkip = framesToSkip;
    backtrace = getBacktrace();
  }

  override int opApply(scope int delegate(ref const(char[])) dg) const {
    printPrettyTrace(backtrace, stdout, options, framesToSkip);
    return 1;
  }

  override int opApply(scope int delegate(ref size_t, ref const(char[])) dg) const {
    printPrettyTrace(backtrace, stdout, options, framesToSkip);
    return 1;
  }

  override string toString() const {
    return "";
  }
}

private static PrintOptions runtimePrintOptions;
private static File runtimeOutputFile;
private static uint runtimeFramesToSkip;

private Throwable.TraceInfo btTraceHandler(void* ptr) {
  return new BTTraceHandler(runtimeOutputFile, runtimePrintOptions, runtimeFramesToSkip);
}

void install(File file, PrintOptions options = PrintOptions.init, uint framesToSkip = 6) {
  import core.runtime;
  runtimePrintOptions = options;
  runtimeOutputFile = file;
  runtimeFramesToSkip = framesToSkip;
  Runtime.traceHandler = &btTraceHandler;
}