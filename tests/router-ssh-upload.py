"""Verify SSH upload arguments remain literal for hostile POSIX file names."""
import contextlib
import importlib.util
import io
import pathlib
import shlex
import tempfile
import types
import unittest
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('router_ssh', pathlib.Path(__file__).parents[1] / 'scripts/xkeen/router_ssh.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class Channel:
    def __init__(self): self.payload = b''
    def recv_exit_status(self): return 0
    def sendall(self, data): self.payload += data
    def shutdown_write(self): pass


class Client:
    def __init__(self): self.commands = []; self.channel = Channel()
    def exec_command(self, command, timeout):
        self.commands.append(command)
        stdin = types.SimpleNamespace(channel=self.channel)
        stdout = types.SimpleNamespace(channel=self.channel, read=lambda: b'4\n')
        return stdin, stdout, types.SimpleNamespace(read=lambda: b'')
    def close(self): pass


class UploadQuotingTests(unittest.TestCase):
    def test_paths_and_mode_remain_single_arguments(self):
        values = ["/opt/test/a b/it's.json", "/opt/test/a'; touch /tmp/SHOULD_NOT_EXIST; #/x.json",
                  '/opt/test/$(id)/`uname`/x.json', '/opt/test/back\\slash/line\nbreak.json']
        with tempfile.TemporaryDirectory() as directory:
            local = pathlib.Path(directory) / 'input'; local.write_bytes(b'a\r\nb\r\n')
            for remote in values:
                for mode in ('644', '755; touch /tmp/SHOULD_NOT_EXIST'):
                    with self.subTest(remote=remote, mode=mode):
                        client = Client()
                        args = types.SimpleNamespace(remote=remote, local=str(local), timeout=10, mode=mode, binary=False)
                        with patch.object(helper, 'open_client', return_value=client), contextlib.redirect_stdout(io.StringIO()):
                            helper.upload_file(args)
                        split = lambda command: list(shlex.shlex(command, posix=True, punctuation_chars=';&|<>'))
                        # shlex.split validates the argv; operator tokenization also catches unquoted shell syntax.
                        self.assertEqual(shlex.split(client.commands[0]), ['mkdir', '-p', '--', helper.posixpath.dirname(remote)])
                        self.assertEqual(shlex.split(client.commands[1]), ['cat', '>', remote])
                        self.assertEqual(shlex.split(client.commands[2]), ['chmod', '--', mode, remote])
                        self.assertEqual(shlex.split(client.commands[3]), ['wc', '-c', '<', remote])
                        self.assertEqual(client.channel.payload, b'a\nb\n')
                        for command in client.commands:
                            self.assertNotIn(';', split(command))
                            self.assertNotIn('&&', split(command))

    def test_binary_bytes_are_not_normalized(self):
        with tempfile.TemporaryDirectory() as directory:
            local = pathlib.Path(directory) / 'asset.png'; local.write_bytes(b'\x89PNG\r\n\x00')
            client = Client()
            args = types.SimpleNamespace(remote='/opt/test/asset.png', local=str(local), timeout=10, mode=None, binary=True)
            with patch.object(helper, 'open_client', return_value=client), contextlib.redirect_stdout(io.StringIO()): helper.upload_file(args)
            self.assertEqual(client.channel.payload, local.read_bytes())


if __name__ == '__main__': unittest.main()
