part of sockfile;

class SendResult {
    final bool successful;
    final List<String> failures;
    SendResult(this.successful, this.failures);

    @override
    String toString() => "SendResult: $successful $failures";
}

class StreamPair {
    final StreamSink<List<int>> send;
    final Stream<List<int>> recv;
    final Function onClose;

    StreamPair(this.send, this.recv, {this.onClose});

    Future close() {
        if (onClose != null) return onClose();
        return send.close();
    }
}

typedef Future<StreamPair> StreamOpener(Uri uri);

StreamOpener _byWebsock = (uri) async {
    var ws = await WebSocket.connect(uri.toString());

    // ignore: argument_type_not_assignable
    return new StreamPair(ws, ws);
};

final Map<String, StreamOpener> _streamOpeners = {
    "tcp": (uri) async {
        var hostname = uri.host;
        var port = 5000;
        var colon = hostname.indexOf(':');
        if (colon >= 0) {
            port = int.parse(hostname.substring(colon+1));
            hostname = hostname.substring(0, colon);
        }

        var socket = await Socket.connect(hostname, port);

        return new StreamPair(socket, socket, onClose: () async {
            // Flush the socket to make sure that the data was sent completely
            await socket.flush();
            // Destroy the socket
            socket.destroy();
        });
    },
    "ws": _byWebsock,
    "wss": _byWebsock,
    "file": (uri) async {
        var notRealFile = new File.fromUri(uri);
        var inputFile = new File(notRealFile.path+"_input");
        var outputFile = new File(notRealFile.path+"_output");

        var read = inputFile.openRead();
        var write = outputFile.openWrite();

        return new StreamPair(write, read, onClose: () {
            return write.close();
        });
    }
};

Future<StreamPair> openStream(Uri uri) {
    var proto = uri.scheme ?? "tcp";
    var opener = _streamOpeners[proto];
    if (opener == null)
        throw new FormatException(
            "Invalid protocol $proto, expected one of: ${_streamOpeners.keys.join(", ")}");
    return opener(uri);
}

Future<SendResult> send(StreamPair pair, List<String> fileNames, {bool verbose: false}) async {
    // This method converts any integer of any width to the byte equivalent
    // Dart automatically switches over to BigInt when you overflow the platform's maximum int
    List<int> toBytes(int i, int width) =>
        new List.generate(width, (idx) => (i >> (width-idx-1)*8) & 0xFF);

    void vprint(String msg) {
        if (verbose) print(msg);
    }

    var sendStream = pair.send;
    // Since we want to read induvidual bytes we iterate over a stream where we
    // expand all our byte lists to bytes
    // This could be made faster by some custom code, but how fast would we
    // really need this to be?
    var byteStreamIterator = new StreamIterator(pair.recv.expand((byteList) => byteList));

    Future<int> nextByte() async {
        await byteStreamIterator.moveNext();
        return byteStreamIterator.current;
    }

    // Write the number of files to the socket
    sendStream.add(toBytes(fileNames.length, 4));

    vprint("Sending files...");

    bool failed = false;
    List<String> sentList;

    // Skip the first argument (the IP address)
    for (String fileName in fileNames) {
        var file = new File(fileName); // Files are really a cover over path elements :P

        // File existence check
        if (!await file.exists()) {
            vprint('File "$fileName" does not exist.');
            failed = true;
            continue;
        }

        // Wait for the first available ack byte
        var ack = await nextByte();
        if (ack == 0) {
            vprint("Send canceled by remote.");
            failed = true;
            break;
        }

        vprint('Sending info for "$fileName"...');

        if (ack >= 2) {
            // Protocol Version Ack
            sendStream.add([255, 255, 255, 255, 255, 255, 255, 255]);

            // Protocol Extension: File name
            var basename = file.uri.pathSegments.last;
            sendStream.add(toBytes(basename.length, 4));
            sendStream.add(UTF8.encode(basename));
        }

        var size = await file.length();
        sendStream.add(toBytes(size, 8)); // Sends the file length as a uint64

        vprint('Sending data for "$fileName"...');
        await sendStream.addStream(file.openRead()); // Adds the data from the file to the stream and waits for it to finish

        vprint('File "$fileName" sent successfully...');

        sentList ??= [];
        sentList.add(fileName);
    }

    var result;

    if (!failed) {
        vprint('All files sent successfully.');
        result = new SendResult(true, null);
    } else {
        vprint('Files sent with errors.');
        result = new SendResult(false, sentList ?? const []);
    }

    await byteStreamIterator.cancel();
    await sendStream.close();
    await pair.close();

    return result;
}
