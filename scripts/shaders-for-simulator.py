#!/usr/bin/env python3
"""Recompile an App Store app's Metal shader library for the iOS simulator.

App Store builds ship shaders compiled only for iPhone GPUs. The simulator
refuses them ("Target OS is incompatible: library was not compiled for the
simulator"), so Plex's background shader never draws and the home screen
stays black. Each shader in the library is LLVM bitcode; this script cuts
them out, recompiles them with a simulator target and packs a new library
in place of the old one.

Needs Apple's Metal toolchain: xcodebuild -downloadComponent MetalToolchain
Usage: shaders-for-simulator.py <file.metallib>
"""
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def shader_modules(data: bytes) -> list[tuple[str, bytes]]:
    """Return (function name, bitcode) for each function in a metallib.

    Header layout: "MTLB" magic, then at byte 24 the function list offset and
    at byte 72 the bitcode section offset. Each function entry is a list of
    tagged fields; NAME holds the name, MDSZ the bitcode size and OFFT three
    offsets, the last of which points into the bitcode section.
    """
    if data[:4] != b"MTLB":
        raise ValueError("not a Metal library")
    list_offset = struct.unpack_from("<Q", data, 24)[0]
    bitcode_offset = struct.unpack_from("<Q", data, 72)[0]
    count = struct.unpack_from("<I", data, list_offset)[0]
    pos = list_offset + 4
    modules = []
    for _ in range(count):
        entry_size = struct.unpack_from("<I", data, pos)[0]
        tag_pos, end = pos + 4, pos + entry_size
        name, size, offset = None, None, None
        while tag_pos < end:
            tag = data[tag_pos:tag_pos + 4]
            if tag == b"ENDT":
                break
            length = struct.unpack_from("<H", data, tag_pos + 4)[0]
            value = data[tag_pos + 6:tag_pos + 6 + length]
            if tag == b"NAME":
                name = value.rstrip(b"\0").decode()
            elif tag == b"MDSZ":
                size = struct.unpack_from("<Q", value)[0]
            elif tag == b"OFFT":
                offset = struct.unpack_from("<QQQ", value)[2]
            tag_pos += 6 + length
        if name is None or size is None or offset is None:
            raise ValueError("function entry without NAME, MDSZ or OFFT")
        start = bitcode_offset + offset
        modules.append((name, data[start:start + size]))
        pos = end
    return modules


def main() -> int:
    library = Path(sys.argv[1])
    data = library.read_bytes()
    modules = shader_modules(data)
    with tempfile.TemporaryDirectory() as tmp:
        compiled = []
        for name, bitcode in modules:
            if re.search(rb"apple-ios[0-9.]+-simulator", bitcode):
                print(f"{library.name}: already built for the simulator")
                return 0
            version = re.search(rb"air64-apple-ios([0-9.]+)", bitcode)
            minos = version.group(1).decode().rstrip(".") if version else "14.5"
            source = Path(tmp, f"{name}.bc")
            source.write_bytes(bitcode)
            target = Path(tmp, f"{name}.air")
            subprocess.run(["xcrun", "-sdk", "iphonesimulator", "metal", "-Wno-override-module",
                            "-target", f"air64-apple-ios{minos}-simulator",
                            "-c", str(source), "-o", str(target)], check=True)
            compiled.append(str(target))
        rebuilt = Path(tmp, "rebuilt.metallib")
        subprocess.run(["xcrun", "-sdk", "iphonesimulator", "metallib", *compiled, "-o", str(rebuilt)], check=True)
        library.write_bytes(rebuilt.read_bytes())
    print(f"{library.name}: rebuilt {len(modules)} shaders for the simulator")
    return 0


if __name__ == "__main__":
    sys.exit(main())
