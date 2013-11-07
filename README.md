backtrace-d
===========

backtrace-d is a library that provides a pretty backtrace for D applications
running under Linux. Its usage is very simple, you'll only need to import the
module `backtrace.backtrace` and call `printPrettyTrace`. Also, make sure that
you compile with debug symbols on. On DMD, for example, use the -g flag.

backtrace-d was tested using DMD 2.063.2 and LDC2 0.12.0.

You can also try the experimental `install` call to make backtraces showing on
exceptions beautiful. This works using DMD compiled applications only for now.

Example on using `printPrettyTrace`
-----------------------------------

    import backtrace.backtrace;
    import std.stdio;

    void main() {
      goToF1();
    }

    void goToF1() {
      goToF2();
    }

    void goToF2(uint i = 0) {
      if (i == 2) {
        printPrettyTrace(stderr); return;
      }
      goToF2(++i);
    }

This will print the following to the standard error:

    Stack trace:
    #1: /path/to/source/app.d line (14) in void app.goToF2(uint)

     (11)
     (12)     void goToF2(uint i = 0) {
     (13)       if (i == 2) {
    >(14)         printPrettyTrace(stderr); return;
     (15)       }
     (16)       goToF2(++i);
     (17)     }

    #2: /path/to/source/app.d line (17) in void app.goToF2(uint)

     (14)         printPrettyTrace(stderr); return;
     (15)       }
     (16)       goToF2(++i);
    >(17)     }

    #3: /path/to/source/app.d line (17) in void app.goToF2(uint)
    #4: /path/to/source/app.d line (10) in void app.goToF1()
    #5: /path/to/source/app.d line (5) in _Dmain
    #6: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void runMain()
    #7: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void tryExec(scope void delegate())
    #8: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void runAll()
    #9: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void tryExec(scope void delegate())
    #10: ?? line (0) in _d_run_main
    #11: ?? line (0) in main
    #12: ?? line (0) in __libc_start_main


Example on using `install`
--------------------------

    import Backtrace = backtrace.backtrace;
    import std.stdio;

    void main() {
      Backtrace.install(stderr);

      goToF1();
    }

    void goToF1() {
      goToF2();
    }

    void goToF2(uint i = 0) {
      if (i == 2) {
        throw new Exception("bye");
      }
      goToF2(++i);
    }

This will print the following to the standard error:

    object.Exception@source/app.d(16): bye
    ----------------
    Stack trace:
    #1: /path/to/source/app.d line (19) in void app.goToF2(uint)

     (16)         throw new Exception("bye");
     (17)       }
     (18)       goToF2(++i);
    >(19)     }

    #2: /path/to/source/app.d line (19) in void app.goToF2(uint)

     (16)         throw new Exception("bye");
     (17)       }
     (18)       goToF2(++i);
    >(19)     }

    #3: /path/to/source/app.d line (12) in void app.goToF1()
    #4: /path/to/source/app.d line (7) in _Dmain
    #5: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void runMain()
    #6: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void tryExec(scope void delegate())
    #7: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void runAll()
    #8: ?? line (0) in extern (C) int rt.dmain2._d_run_main(int, char**, extern (C) int function(char[][])*).void tryExec(scope void delegate())
    #9: ?? line (0) in _d_run_main
    #10: ?? line (0) in main
    #11: ?? line (0) in __libc_start_main
    ----------------


You can customize the way the backtrace is printed using the following options:

    PrintOptions options;
    options.detailedForN = 2;        //number of frames to show code for
    options.numberOfLinesBefore = 3; //number of lines of code to show before the specific line
    options.numberOfLinesAfter  = 3; //number of lines of code to show after the specific line
    options.colored = true;          //enable colored output for the backtrace
    printPrettyTrace(stdout, options);


Documentation
-------------

    //prints the backtrace to `output` using the printing `options` provided. Frames to skip is used to
    //skip frames that belong to the internal code of the library
    void printPrettyTrace(File output, PrintOptions options = PrintOptions.init, uint framesToSkip = 1)

    //install the runtime trace handler to print the backtraces
    void install(File file, PrintOptions options = PrintOptions.init, uint framesToSkip = 6)

    //returns an array of backtrace addresses
    void*[] getBacktrace()

    //returns an array of symbols provided an array of addresses
    Symbol[] getBacktraceSymbols(const(void*[]) backtrace)

    //returns an array of lines and files corresponding to the addresses provided
    //this uses `addr2line` tool internally
    Trace[] getLineTrace(const(void*[]) backtrace)

Work to do and bugs
-------------------

- Inaccurate address to line resolving.
 - Problem could reside in the debug symbols emitted by the compilers or the code that produces backtrace addresses.

- Integrate the library with `Runtime.traceHandler` (work in progress)
 - Problems include missing frame where exception occured.

Feedback and pull requests
--------------------------

Please use Github's issue tracker. I'm also open to pull and feature requests.
