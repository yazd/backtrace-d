//Written in the D programming language

/*
 * Sample program to demonstrate Backtrace.
 *
 * Written by: Jason den Dulk.
 */

module sample;

import std.conv;
import std.string;
import std.array;
import std.algorithm;
import std.stdio;

import backtrace;

void toStdout() {
  writeln("#");
  writeln("# Pretty trace direct to stdout.");
  writeln("#");
  printPrettyTrace();
}

void toStderr() {
  writeln("#");
  writeln("# Pretty trace direct to stderr.");
  writeln("#");
  printPrettyTrace(stderr);
}

void asString() {
  writeln("#");
  writeln("# Pretty trace as a string");
  writeln("#");
  write(prettyTrace());
}

void onException() {
  writeln("#");
  writeln("# Pretty trace after an exception");
  writeln("#");
  throw new Exception("FAIL!");
}

void onError() {
  writeln("#");
  writeln("# Pretty trace after an error");
  writeln("#");
  int[] x = [1,2,3];
  int y = x[5]; // Range violation;
}

void main() {
  backtrace.install();
  writeln("### Backtrace Sample Demo. ###");
  toStdout();
  toStderr();
  asString();
  try {
    onException();
  } catch (Exception e) {
    writeln("# Line by line");
    foreach (i,l;e.info)
      writeln(i,": ",l);
    writeln("# via Throwable.toString()");
    write(e.toString());
  }
  onError();
}
