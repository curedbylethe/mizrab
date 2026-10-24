#!/usr/bin/env python3
"""Builds tagged.mp3, tagged.flac, tagged.ogg and packet-split.ogg from the
committed tone.* fixtures (the last one is synthetic).

Python 3 standard library only, deterministic: no timestamps, no random bytes,
fixed field order, so a second run rewrites identical bytes.

    python3 -I tests/fixtures/gen_tags.py

The outputs are hand-built for tag coverage. They are not playable guarantees.
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))

# The strings tests/tags_test.salam asserts against.
MP3_TITLE = "Tōne Café"  # non-ASCII on purpose: UTF-16 path + JSON round trip
MP3_ARTIST = "Mizrab Tester"
MP3_ALBUM = "Fixture Album"
FLAC_TITLE = "Tone FLAC"
FLAC_ARTIST = "Mizrab Tester"
FLAC_ALBUM = "Fixture Album"
OGG_TITLE = "Música"  # non-ASCII on purpose: the UTF-8 path of the Ogg reader
OGG_ARTIST = "Mizrab Tester"
OGG_ALBUM = "Fixture Album"


def read(name):
    with open(os.path.join(HERE, name), "rb") as f:
        return f.read()


def write(name, data):
    with open(os.path.join(HERE, name), "wb") as f:
        f.write(data)


def syncsafe(n):
    return bytes([(n >> 21) & 127, (n >> 14) & 127, (n >> 7) & 127, n & 127])


def frame(fid, enc, text):
    body = bytes([enc]) + text
    return fid + struct.pack(">I", len(body)) + b"\x00\x00" + body


def tagged_mp3():
    tone = read("tone.mp3")
    assert tone[:3] != b"ID3"
    frames = (
        frame(b"TIT2", 0x01, b"\xff\xfe" + MP3_TITLE.encode("utf-16-le"))
        + frame(b"TPE1", 0x03, MP3_ARTIST.encode("utf-8"))
        + frame(b"TALB", 0x03, MP3_ALBUM.encode("utf-8"))
    )
    return b"ID3\x03\x00\x00" + syncsafe(len(frames)) + frames + tone


def tagged_flac():
    tone = read("tone.flac")
    assert tone[:4] == b"fLaC"
    # Walk the original metadata blocks: keep STREAMINFO, drop any existing
    # VORBIS_COMMENT (the encoder wrote one), keep the frames that follow.
    at, streaminfo = 4, None
    while True:
        head = tone[at]
        size = int.from_bytes(tone[at + 1 : at + 4], "big")
        if head & 127 == 0:
            streaminfo = tone[at + 4 : at + 4 + size]
        at += 4 + size
        if head & 128:
            break
    assert streaminfo is not None and len(streaminfo) == 34
    frames_from = at

    vendor = b"mizrab gen_tags"
    comments = [
        b"TITLE=" + FLAC_TITLE.encode("utf-8"),
        b"ARTIST=" + FLAC_ARTIST.encode("utf-8"),
        b"ALBUM=" + FLAC_ALBUM.encode("utf-8"),
        # audio.tag reads digits only, so "3/12" would parse as 312: number and
        # total are separate keys. The full date is deliberate: it parses as
        # 20040501 and library.ReadTrack folds it back to 2004.
        b"TRACKNUMBER=3",
        b"TRACKTOTAL=12",
        b"DATE=2004-05-01",
    ]
    vc = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(comments))
    for c in comments:
        vc += struct.pack("<I", len(c)) + c

    return (
        b"fLaC"
        + b"\x00" + len(streaminfo).to_bytes(3, "big") + streaminfo  # last-block flag cleared
        + b"\x84" + len(vc).to_bytes(3, "big") + vc  # VORBIS_COMMENT, last-block flag set
        + tone[frames_from:]
    )


# Ogg page CRC: polynomial 0x04C11DB7, initial value 0, no final xor, MSB first,
# over the whole page with its CRC field zeroed.
def _crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
        table.append(r & 0xFFFFFFFF)
    return table


CRC_TABLE = _crc_table()


def ogg_crc(data):
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ CRC_TABLE[((crc >> 24) & 0xFF) ^ b]
    return crc


def lacing(n):
    return [255] * (n // 255) + [n % 255]


def ogg_page(flags, granule, serial, seq, segments, body):
    head = (
        b"OggS\x00" + bytes([flags]) + struct.pack("<qIII", granule, serial, seq, 0)
        + bytes([len(segments)]) + bytes(segments)
    )
    page = head + body
    return page[:22] + struct.pack("<I", ogg_crc(page)) + page[26:]


def vorbis_comment_packet(comments):
    vendor = b"mizrab gen_tags"
    pkt = b"\x03vorbis" + struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(comments))
    for c in comments:
        pkt += struct.pack("<I", len(c)) + c
    return pkt + b"\x01"  # framing bit


def tagged_ogg():
    tone = read("tone.ogg")
    # Page 0 holds the identification packet alone, page 1 the comment and
    # setup packets, both complete. Everything after page 1 is audio, copied
    # byte for byte (its CRCs stay valid because nothing in it changes).
    assert tone[:4] == b"OggS" and tone[5] == 0x02
    p1 = 27 + tone[26] + sum(tone[27 : 27 + tone[26]])
    assert tone[p1 : p1 + 4] == b"OggS" and tone[p1 + 5] == 0
    nseg = tone[p1 + 26]
    segs = list(tone[p1 + 27 : p1 + 27 + nseg])
    body = tone[p1 + 27 + nseg : p1 + 27 + nseg + sum(segs)]
    assert segs[-1] < 255 and body[:7] == b"\x03vorbis"
    cut, at = 0, 0
    for s in segs:  # length of the original comment packet
        at += s
        if s < 255:
            cut = at
            break
    setup = body[cut:]
    assert setup[:7] == b"\x05vorbis"
    comments = [
        b"TITLE=" + OGG_TITLE.encode("utf-8"),
        b"ARTIST=" + OGG_ARTIST.encode("utf-8"),
        b"Album=" + OGG_ALBUM.encode("utf-8"),  # mixed case: keys are case-insensitive
        b"TRACKNUMBER=3/12",
        b"DISCNUMBER=1",
        b"DATE=2004-05-01",
        b"METADATA_BLOCK_PICTURE=AAAA",  # must be ignored
    ]
    comment = vorbis_comment_packet(comments)
    segments = lacing(len(comment)) + lacing(len(setup))
    serial = struct.unpack("<I", tone[14:18])[0]
    page1 = ogg_page(0, 0, serial, 1, segments, comment + setup)
    return tone[:p1] + page1 + tone[p1 + 27 + nseg + sum(segs) :]


def packet_split_ogg():
    """Synthetic, not audio: a comment packet that crosses a page boundary."""
    serial = 0x4D5A5242
    ident = b"\x01vorbis" + struct.pack("<IBIiiiBB", 0, 1, 22050, 0, 0, 0, 0xB8, 1)
    assert len(ident) == 30
    comments = [
        b"TITLE=" + OGG_TITLE.encode("utf-8"),
        b"FILLER=" + b"x" * 500,  # pushes the packet past two 255 byte segments
        b"ARTIST=" + OGG_ARTIST.encode("utf-8"),
        b"ALBUM=" + OGG_ALBUM.encode("utf-8"),
    ]
    comment = vorbis_comment_packet(comments)
    assert 510 < len(comment) < 765
    setup = b"\x05vorbis" + b"\x00" * 3
    rest = comment[510:]
    return (
        ogg_page(0x02, 0, serial, 0, lacing(len(ident)), ident)
        # page 1 ends on a 255 lacing value: the packet continues
        + ogg_page(0, -1, serial, 1, [255, 255], comment[:510])
        # page 2 is flagged "continued" and carries the rest, then the setup packet
        + ogg_page(0x01, 0, serial, 2, lacing(len(rest)) + lacing(len(setup)), rest + setup)
        + ogg_page(0x04, 0, serial, 3, [0], b"")
    )


if __name__ == "__main__":
    write("tagged.mp3", tagged_mp3())
    write("tagged.flac", tagged_flac())
    write("tagged.ogg", tagged_ogg())
    write("packet-split.ogg", packet_split_ogg())
