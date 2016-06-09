library sockfile;

import 'dart:io';

// Comments are great
void main(List<String> args) async {
    if (args.length < 2) {
        stderr.writeln("Usage: sockfile <ip> <files...>");
        return;
    }

    // This method converts any integer of any width to the byte equivalent
    // Dart automatically switches over to BigInt when you overflow the platform's maximum int
    List<int> toBytes(int i, int width) =>
        new List.generate(width, (idx) => (i >> (width-idx-1)*8) & 0xFF);

    // Super ultra convenient method that opens a socket asynchronously
    var socket = await Socket.connect(args[0], 5000);
    // Sockets extend Stream<List<int>> and Sink<List<int>>. We want to be able to access a single byte (for file ack)
    // This is done by expanding the list and converting the stream into a broadcast stream
    var byteStream = socket.expand((byteList) => byteList).asBroadcastStream();

    // Write the number of files to the socket
    socket.add(toBytes(args.length-1, 4));

    print("Sending files...");

    bool failed = false;

    // Skip the first argument (the IP address)
    for (String fileName in args.skip(1)) {
        var file = new File(fileName); // Files are really a cover over path elements :P

        // File existence check
        if (!await file.exists()) {
            print('File "$fileName" does not exist.');
            failed = true;
            continue;
        }

        // Wait for the first available ack byte
        var ack = await byteStream.first;
        if (ack == 0) {
            print("Send canceled by remote.");
            failed = true;
            break;
        }

        print('Sending info for "$fileName"...');
        var size = await file.length();
        socket.add(toBytes(size, 8)); // Sends the file length as a uint64

        print('Sending data for "$fileName"...');
        await socket.addStream(file.openRead()); // Adds the data from the file to the stream and waits for it to finish

        print('File "$fileName" sent successfully...');
    }

    if (!failed) {
        print('All files sent successfully.');
    } else {
        print('Files sent with errors.');
    }

    // Flush the socket to make sure that the data was sent completely
    await socket.flush();
    // Destroy the socket
    socket.destroy();
}
