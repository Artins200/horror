#!/usr/bin/env python3
"""
Вшивает скрипты игры в бинарный Roblox place (.rbxl), ничего больше не трогая.

Зачем так: в 13123.rbxl уже лежат ровно два скрипта —
  * ServerScriptService > Script        (classId класса Script, 1 инстанс)
  * StarterPlayerScripts > LocalScript  (classId класса LocalScript, 1 инстанс)
У бинарного формата .rbxl свойство Source лежит в PROP-чанке простым
length-prefixed string, поэтому можно заменить только эти два чанка,
пересжать их zstd (формат так и хранился) и получить готовый к игре файл.

Использование:
    pip install zstandard
    python3 tools/build_place.py \
        --original 13123_original.rbxl --output 13123.rbxl \
        --server src/server/HorrorGameServer.server.lua \
        --client src/client/HorrorClient.client.lua

По умолчанию берёт пути из корня репозитория именно такие.
"""

from __future__ import annotations

import argparse
import pathlib
import struct
import sys

try:
    import zstandard as zstd
except ImportError:
    sys.exit("Нужен пакет zstandard:  pip install zstandard")


HEADER_SIZE = 32  # "<roblox!" + signature + version + classCount + instanceCount + reserved


def read_chunks(data: bytes):
    """Возвращает список (name, comp_len, uncomp_len, header_offset, data_offset)."""
    chunks = []
    off = HEADER_SIZE
    while off + 16 <= len(data):
        name = data[off : off + 4]
        comp_len, uncomp_len, _reserved = struct.unpack("<III", data[off + 4 : off + 16])
        chunks.append((name, comp_len, uncomp_len, off, off + 16))
        if name == b"END\x00":
            break
        off += 16 + (comp_len if comp_len != 0 else uncomp_len)
    return chunks


def decompress_chunk(data: bytes, chunk) -> bytes:
    _name, comp_len, uncomp_len, _hoff, doff = chunk
    if comp_len == 0:
        return data[doff : doff + uncomp_len]
    raw = data[doff : doff + comp_len]
    if raw[:4] == bytes.fromhex("28b52ffd"):
        out = zstd.ZstdDecompressor().decompress(raw, max_output_size=uncomp_len)
    else:
        raise ValueError(f"Неизвестная компрессия чанка {_name!r} (не zstd)")
    assert len(out) == uncomp_len, (len(out), uncomp_len)
    return out


def parse_inst_classes(data: bytes, chunks) -> dict[int, tuple[str, int]]:
    classes: dict[int, tuple[str, int]] = {}
    for chunk in chunks:
        if chunk[0] != b"INST":
            continue
        dec = decompress_chunk(data, chunk)
        class_id = struct.unpack("<I", dec[:4])[0]
        name_len = struct.unpack("<I", dec[4:8])[0]
        class_name = dec[8 : 8 + name_len].decode("utf-8")
        count = struct.unpack("<I", dec[9 + name_len : 13 + name_len])[0]
        classes[class_id] = (class_name, count)
    return classes


def replace_source_in_chunk(dec: bytes, new_source: bytes) -> bytes:
    """PROP-чанк свойства Source: [classId][len+propName][type=1][len+value]..."""
    class_id = struct.unpack("<I", dec[:4])[0]
    name_len = struct.unpack("<I", dec[4:8])[0]
    prop_name = dec[8 : 8 + name_len].decode("utf-8")
    assert prop_name == "Source", prop_name
    type_byte = dec[8 + name_len]
    assert type_byte == 1, f"Ожидался string type=1, получен {type_byte}"
    pos = 9 + name_len
    values = []
    # В наших классах по 1 инстансу, но код честно проходит все значения;
    # заменяем только первое (единственное) — остальные не трогаем.
    first = True
    while pos < len(dec):
        (ln,) = struct.unpack("<I", dec[pos : pos + 4])
        pos += 4
        old = dec[pos : pos + ln]
        pos += ln
        values.append(new_source if first else old)
        first = False
    out = bytearray()
    out += struct.pack("<I", class_id)
    out += struct.pack("<I", name_len) + prop_name.encode("utf-8")
    out += bytes([type_byte])
    for v in values:
        out += struct.pack("<I", len(v)) + v
    return bytes(out)


def find_source_chunks(data: bytes, chunks, classes):
    """{class_name: (chunk_index, decompressed_bytes)} для классов со свойством Source."""
    found = {}
    index_by_offset = {c[3]: i for i, c in enumerate(chunks)}
    for chunk in chunks:
        if chunk[0] != b"PROP":
            continue
        dec = decompress_chunk(data, chunk)
        if len(dec) < 9:
            continue
        name_len = struct.unpack("<I", dec[4:8])[0]
        if name_len > 64:
            continue
        prop_name = dec[8 : 8 + name_len]
        if prop_name != b"Source":
            continue
        class_id = struct.unpack("<I", dec[:4])[0]
        class_name, count = classes[class_id]
        found[class_name] = (index_by_offset[chunk[3]], dec, count)
    return found


def build(original: pathlib.Path, output: pathlib.Path, server_src: pathlib.Path, client_src: pathlib.Path):
    data = original.read_bytes()
    assert data[:8] == b"<roblox!", "Это не бинарный .rbxl"
    chunks = read_chunks(data)
    classes = parse_inst_classes(data, chunks)
    sources = find_source_chunks(data, chunks, classes)

    replacements: dict[int, bytes] = {}  # chunk_index -> новый decompressed payload
    for class_name, path in (("Script", server_src), ("LocalScript", client_src)):
        if class_name not in sources:
            raise SystemExit(f"В place не найден PROP Source для класса {class_name}")
        chunk_index, dec, count = sources[class_name]
        if count != 1:
            raise SystemExit(f"Ожидался 1 инстанс {class_name}, найдено {count} — билдер надо расширить")
        new_source = path.read_bytes()
        new_dec = replace_source_in_chunk(dec, new_source)
        replacements[chunk_index] = new_dec
        print(f"{class_name}: Source {len(dec)} -> {len(new_dec)} байт ({path})")

    out = bytearray(data[:HEADER_SIZE])
    compressor = zstd.ZstdCompressor(level=3)
    for i, chunk in enumerate(chunks):
        name, _cl, _ul, _hoff, _doff = chunk
        if name == b"END\x00":
            out += data[chunk[3] : chunk[3] + 16 + 9]  # END + "</roblox>"
            break
        if i in replacements:
            payload = replacements[i]
            comp = compressor.compress(payload)
            out += name + struct.pack("<III", len(comp), len(payload), 0) + comp
        else:
            comp_len, uncomp_len = chunk[1], chunk[2]
            raw_len = comp_len if comp_len != 0 else uncomp_len
            out += data[chunk[3] : chunk[4] + raw_len]  # чанк как был, байт-в-байт
    output.write_bytes(bytes(out))
    print(f"Записано: {output} ({len(out)} байт, было {len(data)})")

    # ---- Верификация: перечитываем результат тем же парсером ----
    check = output.read_bytes()
    chunks2 = read_chunks(check)
    assert len(chunks2) == len(chunks), (len(chunks2), len(chunks))
    classes2 = parse_inst_classes(check, chunks2)
    assert classes2 == classes, "Карта классов изменилась!"
    sources2 = find_source_chunks(check, chunks2, classes2)
    for class_name, path in (("Script", server_src), ("LocalScript", client_src)):
        _idx, dec, _count = sources2[class_name]
        name_len = struct.unpack("<I", dec[4:8])[0]
        pos = 9 + name_len  # [classId 4][len 4][name][type 1] -> первое значение
        (ln,) = struct.unpack("<I", dec[pos : pos + 4])
        pos += 4
        value = dec[pos : pos + ln]
        assert value == path.read_bytes(), f"Source {class_name} после сборки не совпал с файлом!"
    print("Верификация OK: оба Source на месте, остальные чанки и классы не тронуты.")


def main():
    ap = argparse.ArgumentParser(description="Вшить скрипты хоррор-лестницы в .rbxl")
    ap.add_argument("--original", default="13123_original.rbxl")
    ap.add_argument("--output", default="13123.rbxl")
    ap.add_argument("--server", default="src/server/HorrorGameServer.server.lua")
    ap.add_argument("--client", default="src/client/HorrorClient.client.lua")
    args = ap.parse_args()
    build(pathlib.Path(args.original), pathlib.Path(args.output),
          pathlib.Path(args.server), pathlib.Path(args.client))


if __name__ == "__main__":
    main()
