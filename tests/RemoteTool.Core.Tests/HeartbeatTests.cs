using System.Buffers.Binary;
using System.Diagnostics;
using RemoteTool.Core.Protocol;
using RemoteTool.Core.Session;

namespace RemoteTool.Core.Tests;

public class HeartbeatTests
{
    /// <summary>Delivers one byte per read after a delay, so a frame "arrives" slowly; never returns EOF until the data is used up.</summary>
    private sealed class DripStream : Stream
    {
        private readonly byte[] _data; private int _pos; private readonly int _delayMs;
        public DripStream(byte[] data, int delayMs) { _data = data; _delayMs = delayMs; }
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default)
        {
            if (_pos >= _data.Length) { await Task.Delay(Timeout.Infinite, ct); return 0; }
            await Task.Delay(_delayMs, ct);
            buffer.Span[0] = _data[_pos++];
            return 1;
        }
        public override bool CanRead => true; public override bool CanSeek => false; public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException(); public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { } public override int Read(byte[] b, int o, int c) => throw new NotSupportedException();
        public override long Seek(long o, SeekOrigin s) => throw new NotSupportedException(); public override void SetLength(long v) => throw new NotSupportedException();
        public override void Write(byte[] b, int o, int c) => throw new NotSupportedException();
    }

    /// <summary>A write that never completes (the link is stalled).</summary>
    private sealed class StalledWriteStream : Stream
    {
        public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken ct = default) => new(Task.Delay(Timeout.Infinite, ct));
        public override Task FlushAsync(CancellationToken ct) => Task.CompletedTask;
        public override bool CanRead => false; public override bool CanSeek => false; public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException(); public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { } public override int Read(byte[] b, int o, int c) => throw new NotSupportedException();
        public override long Seek(long o, SeekOrigin s) => throw new NotSupportedException(); public override void SetLength(long v) => throw new NotSupportedException();
        public override void Write(byte[] b, int o, int c) { }
    }

    [Fact]
    public async Task FrameReader_CountsPartialFrameBytesAsActivity()
    {
        var frame = new byte[5 + 3]; BinaryPrimitives.WriteUInt32BigEndian(frame, 3); frame[4] = (byte)MessageType.Ping;
        var reader = new FrameReader(new DripStream(frame, 40), _ => true, 1024);
        var before = reader.LastActivityTimestamp;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var read = reader.ReadAsync(cts.Token).AsTask();
        await Task.Delay(100);                                   // mid-frame: a few bytes have arrived, the frame is not complete
        Assert.False(read.IsCompleted);
        Assert.True(reader.LastActivityTimestamp > before);
        await read;
    }

    [Fact]
    public async Task SessionPump_StillTimesOutWhenTheOutgoingLinkIsStalled_InsteadOfFreezing()
    {
        // Peer sends nothing and our writes never complete. The old loop awaited the ping write and never evaluated the timeout.
        var reader = new FrameReader(new DripStream(Array.Empty<byte>(), 10), _ => true, 1024);
        var writer = new FrameWriter(new StalledWriteStream());
        var pump = new SessionPump(reader, writer, _ => ValueTask.CompletedTask, TimeSpan.FromMilliseconds(50), TimeSpan.FromMilliseconds(300));
        var sw = Stopwatch.StartNew();
        await Assert.ThrowsAsync<TimeoutException>(() => pump.RunAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.True(sw.Elapsed < TimeSpan.FromSeconds(5));
    }
}
