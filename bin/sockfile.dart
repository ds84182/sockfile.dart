library sockfile.bin;

import 'package:sockfile/sockfile.dart' as sockfile;

// Comments are great
int main(List<String> args) async {
    if (args.length < 2) {
        stderr.writeln("Usage: sockfile <ip> <files...>");
        return;
    }

    var result = await sockfile.send(args[0], args.skip(1).toList(), verbose: true);

    return result.succeeded ? 0 : 1;
}
