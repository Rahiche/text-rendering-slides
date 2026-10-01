import 'dart:io';

/// Resident memory of this process, in MB.
int currentRssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

void perfLine(String line) => stdout.writeln(line);

/// An environment variable (perf builds read their test knobs from these).
String? perfEnv(String key) => Platform.environment[key];
