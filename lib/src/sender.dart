part of sockfile;

class SendResult {
    final bool successful;
    final List<String> failures;
    SendResult(this.successful, this.failures);

    @override
    String toString() => "SendResult: $successful $failures";
}

Future<SendResult> send(String ipAddr, List<String> fileNames, {bool verbose: false}) async {
    // This method converts any integer of any width to the byte equivalent
    // Dart automatically switches over to BigInt when you overflow the platform's maximum int
    List<int> toBytes(int i, int width) =>
        new List.generate(width, (idx) => (i >> (width-idx-1)*8) & 0xFF);

    void vprint(String msg) {
        if (verbose) print(msg);
    }

    // Super ultra convenient method that opens a socket asynchronously
    var socket = await Socket.connect(ipAddr, 5000);
    // Sockets extend Stream<List<int>> and Sink<List<int>>. We want to be able to access a single byte (for file ack)
    // This is done by expanding the list and converting the stream into a broadcast stream
    var byteStream = socket.expand((byteList) => byteList).asBroadcastStream();

    // Write the number of files to the socket
    socket.add(toBytes(fileNames.length, 4));

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
        var ack = await byteStream.first;
        if (ack == 0) {
            vprint("Send canceled by remote.");
            failed = true;
            break;
        }

        vprint('Sending info for "$fileName"...');

        if (ack >= 2) {
            // Protocol Version Ack
            socket.add([255, 255, 255, 255, 255, 255, 255, 255]);

            // Protocol Extension: File name
            var basename = file.uri.pathSegments.last;
            socket.add(toBytes(basename.length, 4));
            socket.add(UTF8.encode(basename));
        }

        var size = await file.length();
        socket.add(toBytes(size, 8)); // Sends the file length as a uint64

        vprint('Sending data for "$fileName"...');
        await socket.addStream(file.openRead()); // Adds the data from the file to the stream and waits for it to finish

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

    // Flush the socket to make sure that the data was sent completely
    await socket.flush();
    // Destroy the socket
    socket.destroy();

    return result;
}
