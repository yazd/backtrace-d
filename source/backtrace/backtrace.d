//Written in the D programming language

module backtrace.backtrace;

version(linux) {
  // allow only linux platform
} else {
  pragma(msg, "backtrace only works in a Linux environment");
}

version(linux):

import std.stdio;
import core.sys.linux.execinfo;

private enum maxBacktraceSize = 32;
private alias TraceHandler = Throwable.TraceInfo function(void* ptr);

extern (C) void* thread_stackBottom();

struct Trace {
  string file;
  uint line;
}

struct Symbol {
  string line;

  string demangled() const {
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
  bool stopAtDMain = true;
}

version(DigitalMars) {

  void*[] getBacktrace() {
    enum CALL_INST_LENGTH = 1; // I don't know the size of the call instruction
                               // and whether it is always 5. I picked 1 instead
                               // because it is enough to get the backtrace
                               // to point at the call instruction
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
        buffer[traceSize++] = (*(stackPtr + 1)) - CALL_INST_LENGTH;
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

  foreach (i, bt; backtrace) {
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

void printPrettyTrace(PrintOptions options = PrintOptions.init, uint framesToSkip = 1) {
  void*[] bt = getBacktrace();
  auto or = stdout.lockingTextWriter();
  printPrettyTrace(bt, or, options, framesToSkip);
}

void printPrettyTrace(File output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1) {
  void*[] bt = getBacktrace();
  auto or = output.lockingTextWriter();
  printPrettyTrace(bt, or, options, framesToSkip);
}

void printPrettyTrace(OR)(ref OR output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1) {
  void*[] bt = getBacktrace();
  printPrettyTrace(bt, output, options, framesToSkip);
}

private void printPrettyTrace(OR)(const(void*[]) bt, ref OR output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1, bool insertNewlines = true) {
  import std.algorithm : max;
  import std.range;
  import std.format;

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

  output.put("Stack trace:");
  if (insertNewlines) output.put("\n");

  foreach(i, t; trace.drop(framesToSkip)) {
    auto symbol = symbols[framesToSkip + i].demangled;
    auto s = appender!string();
    formattedWrite(
      s,
      "#%d: %s%s%s line %s (%s)%s%s%s%s%s @ %s0x%s%s",
      i+1,
      forecolor(Color.red),
      t.file,
      reset(),
      forecolor(Color.yellow),
      t.line,
      reset(),
      symbol.length == 0 ? "" : " in ",
      forecolor(Color.green),
      symbol,
      reset(),
      forecolor(Color.green),
      bt[i + 1],
      reset()
    );
    output.put(s.data);
    if (insertNewlines) output.put("\n");

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
      output.put(insertNewlines?"\n":"");
      foreach (line; lines.take(endingLine - startingLine)) {
        auto s2 = appender!string();
        formattedWrite(
          s2,
          "%s%s(%d)%s%s",
          forecolor(t.line == lineNumber ? Color.yellow : Color.cyan),
          t.line == lineNumber ? ">" : " ",
          lineNumber,
          forecolor(t.line == lineNumber ? Color.yellow : Color.blue),
          line
        );
        output.put(s2.data);
        if (insertNewlines) output.put("\n");
        lineNumber++;
      }
      output.put(reset());
      if (insertNewlines) output.put("\n");
    }

    if (options.stopAtDMain && symbol == "_Dmain") break;
  }
}

// TODO. I imagine something like this is available somewhere in Phobos.

private struct DelegateOutputRange1
{
  int delegate(ref const(char[])) dg;

  void put(const(char[]) s) { dg(s); }
}

private struct DelegateOutputRange2
{
  int delegate(ref size_t, ref const(char[])) dg;

  private size_t i = 0;

  void put(const(char[]) s) { dg(i,s); i++; }
}

private class BTTraceHandler : Throwable.TraceInfo {
  void*[] backtrace;
  PrintOptions options;
  uint framesToSkip;

  this(PrintOptions options, uint framesToSkip) {
    this.options = options;
    this.framesToSkip = framesToSkip;
    backtrace = getBacktrace();
  }

  override int opApply(scope int delegate(ref const(char[])) dg) const {
    auto or = DelegateOutputRange1(dg);
    printPrettyTrace(backtrace, or, options, framesToSkip, false);
    return 1;
  }

  override int opApply(scope int delegate(ref size_t, ref const(char[])) dg) const {
    auto or = DelegateOutputRange2(dg);
    printPrettyTrace(backtrace, or, options, framesToSkip, false);
    return 1;
  }

  override string toString() const {
    import std.array;
    auto buf = appender!string();
    printPrettyTrace(backtrace, buf, options, framesToSkip);

    return buf.data;
  }
}

private static PrintOptions runtimePrintOptions;
private static uint runtimeFramesToSkip;

private Throwable.TraceInfo btTraceHandler(void* ptr) {
  return new BTTraceHandler(runtimePrintOptions, runtimeFramesToSkip);
}

// This is kept for backwards compatibility, however, file was never used
// so it is redundant.
void install(File file, PrintOptions options = PrintOptions.init, uint framesToSkip = 5) {
  install(options, framesToSkip);
}

void install(PrintOptions options = PrintOptions.init, uint framesToSkip = 5) {
  import core.runtime;
  runtimePrintOptions = options;
  runtimeFramesToSkip = framesToSkip;
  Runtime.traceHandler = &btTraceHandler;
}
