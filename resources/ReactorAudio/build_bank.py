"""Build the one-shot from Noita's FMOD 2.01.05 modding example and PCM master.

Usage: python build_bank.py path/to/Noita
"""
import hashlib
from pathlib import Path
import struct
import sys
import uuid
import wave
import xml.etree.ElementTree as ET


source = Path(__file__).resolve().parent
output = source.parents[1] / "mods/noita_hideout/files/reactor_audio"
project = Path(sys.argv[1]) / "tools_modding/noita-fmod-project"
template = project / "Build/Desktop/my_mod_audio.bank"
bank = bytearray(template.read_bytes())
fsb_pos = bank.index(b"FSB5")
assert bank[8:12] == b"FEV " and bank.count(b"FSB5") == 1

def field(chunk, relative):
    assert bank.count(chunk, 0, fsb_pos) == 1, chunk
    return bank.index(chunk) + 8 + relative

def replace_float(chunk, offset, old, new):
    at = field(chunk, offset)
    assert abs(struct.unpack_from("<f", bank, at)[0] - old) < 1e-5
    struct.pack_into("<f", bank, at, new)

def reserve_id(old):
    old_id = uuid.UUID(old.strip("{}"))
    new_id = uuid.uuid5(uuid.NAMESPACE_URL, "noita-hideout/mana-reactor/" + str(old_id))
    bank[:fsb_pos] = bank[:fsb_pos].replace(old_id.bytes_le, new_id.bytes_le)
    return new_id


# Keep the game's output bus, spatialiser and optional ambient lowpass. Give
# all objects owned by the new event their own IDs so the example can coexist.
original_event = "c7d655d8-ec85-4d25-bc91-cf2cca64fbb7"
objects = ET.parse(project / "Metadata/Event" / ("{" + original_event + "}.xml"))
for obj in objects.findall("object"):
    if obj.get("class") != "Event":
        reserve_id(obj.attrib["id"])
event_id = reserve_id(original_event)
bank_id = reserve_id("91582d81-bc04-4e28-971c-5f71aeefedd7")
reserve_id("144e94b1-f5f8-443b-bf1a-c33c046c6851")  # sample

# The example's one-shot has a -6 semitone offset and random pitch. The
# recorded siren already contains the exact pitch sweep that should play.
replace_float(b"INST", 20, -6, 0)
replace_float(b"MODB", 46, 8.33333397, 0)
with wave.open(str(source / "reactor_warning.wav"), "rb") as wav:
    assert (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) == (48000, 1, 2)
    frames = wav.getnframes()
    samples = wav.readframes(frames)

# FEV timeline positions are in 48 kHz samples. Its async instrument also
# plays to the end of the FSB sound. Give both the same duration.
timeline_length = field(b"TLNB", 40)
assert struct.unpack_from("<I", bank, timeline_length)[0] == 48000
struct.pack_into("<I", bank, timeline_length, frames)

# An FSB5 with a single 48 kHz mono PCM16 sample. Its mode/rate bits describe
# the source directly; no encoder, runtime conversion or external audio paths.
sample_header = struct.pack("<Q", (frames << 34) | (9 << 1))
name_table = struct.pack("<I", 4) + b"reactor_warning\0"
pcm = samples + bytes(-len(samples) % 32)
fsb = (struct.pack("<4s6I", b"FSB5", 1, 1, len(sample_header), len(name_table), len(pcm), 2)
       + bytes(16) + hashlib.sha256(samples).digest()[:16] + sample_header + name_table + pcm)
header = field(b"SNDH", 4)
sample_chunk = field(b"SND ", 0)
assert struct.unpack_from("<II", bank, header) == (fsb_pos, len(bank) - fsb_pos)
struct.pack_into("<I", bank, header + 4, len(fsb))
struct.pack_into("<I", bank, sample_chunk - 4, fsb_pos - sample_chunk + len(fsb))
bank[fsb_pos:] = fsb
struct.pack_into("<I", bank, 4, len(bank) - 8)

output.mkdir(parents=True, exist_ok=True)
(output / "nh_reactor_alarm.bank").write_bytes(bank)
(output / "events.txt").write_text(
    f"{{{bank_id}}} bank:/nh_reactor_alarm\n{{{event_id}}} event:/nh_reactor/warning\n",
    encoding="utf-8", newline="\n")
print(f"{frames} frames, {event_id=}, {bank_id=}")
