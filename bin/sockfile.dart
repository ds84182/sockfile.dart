library sockfile.bin;

import 'package:sockfile/sockfile.dart' as sockfile;

import 'dart:async';
import 'dart:io';

// Comments are great
Future<int> main(List<String> args) async {
    if (args.length < 2) {
        stderr.writeln("Usage: sockfile <ip> <files...>");
        return exitInvalidArgs;
    }

    var pair = await sockfile.openStream(Uri.parse(args[0]));
    var result = await sockfile.send(pair, args.skip(1).toList(), verbose: true);

    return result.successful ? exitSuccess : exitFailure;
}

const exitSuccess = 0;
const exitFailure = 1;
const exitInvalidArgs = 2;
