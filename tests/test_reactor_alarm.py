from pathlib import Path
import struct
import unittest
import uuid
import wave


ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "mods/noita_hideout/files"


class ReactorAlarm(unittest.TestCase):
    def test_event_ids_sample_and_timeline_match_the_delivered_warning(self):
        audio = FILES / "reactor_audio"
        controller = (FILES.parent / "init.lua").read_text(encoding="utf-8")
        on_init = controller.split("function OnModInit()", 1)[1].split("\nfunction ", 1)[0]
        self.assertIn('ModRegisterAudioEventMappings(files.."reactor_audio/events.txt")', on_init)
        mapping = {}
        for line in (audio / "events.txt").read_text().splitlines():
            identifier, name = line.split()
            mapping[name] = uuid.UUID(identifier)
        self.assertEqual(set(mapping), {"bank:/nh_reactor_alarm", "event:/nh_reactor/warning"})
        script = (FILES / "reactor_alarm.lua").read_text()
        self.assertIn('GamePlaySound("mods/noita_hideout/files/reactor_audio/nh_reactor_alarm.bank","nh_reactor/warning",x,y)', script)

        bank = (audio / "nh_reactor_alarm.bank").read_bytes()
        self.assertEqual(bank[:4], b"RIFF")
        self.assertEqual(bank[8:12], b"FEV ")
        self.assertEqual(struct.unpack_from("<I", bank, 4)[0], len(bank) - 8)
        bank_info = bank.index(b"BNKI") + 8
        event = bank.index(b"EVTB") + 8
        self.assertEqual(bank[bank_info:bank_info + 16], mapping["bank:/nh_reactor_alarm"].bytes_le)
        self.assertEqual(bank[event:event + 16], mapping["event:/nh_reactor/warning"].bytes_le)
        with wave.open(str(ROOT / "resources/ReactorAudio/reactor_warning.wav")) as master:
            self.assertEqual((master.getframerate(), master.getnchannels(), master.getsampwidth()), (48000, 1, 2))
            frames = master.getnframes()
            pcm = master.readframes(frames)
        self.assertEqual(frames, 201600)
        self.assertEqual(struct.unpack_from("<I", bank, bank.index(b"TLNB") + 8 + 40)[0], frames)
        start, length = struct.unpack_from("<II", bank, bank.index(b"SNDH") + 12)
        self.assertEqual(start + length, len(bank))
        tag, version, count, headers, names, size, mode = struct.unpack_from("<4s6I", bank, start)
        self.assertEqual((tag, version, count, mode), (b"FSB5", 1, 1, 2))
        sample = struct.unpack_from("<Q", bank, start + 60)[0]
        self.assertEqual(sample >> 34, frames)
        self.assertEqual(sample & 255, 9 << 1)  # single-channel 48 kHz
        data = start + 60 + headers + names
        self.assertEqual(bank[data:data + len(pcm)], pcm)
        self.assertEqual(size, len(bank) - data)

        other = (FILES / "storm/audio/events.txt").read_text()
        for identifier in mapping.values():
            self.assertNotIn(str(identifier), other)
