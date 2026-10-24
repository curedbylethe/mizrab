#!/usr/bin/env python3
"""Builds tagged.mp3 and tagged.flac from the committed tone.* fixtures.

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


if __name__ == "__main__":
    write("tagged.mp3", tagged_mp3())
    write("tagged.flac", tagged_flac())
