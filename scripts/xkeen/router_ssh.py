#!/usr/bin/env python3
import argparse
import os
import posixpath
import stat
import sys

import paramiko


def get_password(args: argparse.Namespace) -> str:
    password = args.password or os.environ.get("ROUTER_SSH_PASSWORD")
    if not password:
        raise SystemExit("Set ROUTER_SSH_PASSWORD or pass --password.")
    return password


def open_client(args: argparse.Namespace) -> paramiko.SSHClient:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=args.host,
        port=args.ssh_port,
        username=args.user,
        password=get_password(args),
        timeout=args.timeout,
        banner_timeout=args.timeout,
        auth_timeout=args.timeout,
        look_for_keys=False,
        allow_agent=False,
    )
    return client


def run_command(args: argparse.Namespace) -> int:
    client = open_client(args)
    try:
        command = sys.stdin.read() if args.stdin else args.command
        if not command:
            raise SystemExit("Command is empty.")
        _, stdout, stderr = client.exec_command(command, timeout=args.timeout)
        exit_code = stdout.channel.recv_exit_status()
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)
        return exit_code
    finally:
        client.close()


def mkdirs_sftp(sftp: paramiko.SFTPClient, remote_dir: str) -> None:
    parts = []
    current = remote_dir
    while current not in ("", "/"):
        parts.append(current)
        current = posixpath.dirname(current)
    for path in reversed(parts):
        try:
            sftp.stat(path)
        except FileNotFoundError:
            sftp.mkdir(path)


def upload_file(args: argparse.Namespace) -> int:
    client = open_client(args)
    try:
        remote_dir = posixpath.dirname(args.remote)
        mkdir_stdin = client.exec_command(f"mkdir -p '{remote_dir}'", timeout=args.timeout)
        mkdir_exit = mkdir_stdin[1].channel.recv_exit_status()
        if mkdir_exit != 0:
            raise SystemExit(f"Failed to create remote directory: {remote_dir}")

        with open(args.local, "rb") as local_file:
            stdin, stdout, stderr = client.exec_command(
                f"cat > '{args.remote}'", timeout=args.timeout
            )
            stdin.channel.sendall(local_file.read())
            stdin.channel.shutdown_write()
            exit_code = stdout.channel.recv_exit_status()
            err = stderr.read().decode("utf-8", errors="replace")
            if exit_code != 0:
                raise SystemExit(err or f"Failed to upload file to {args.remote}")

        if args.mode:
            _, stdout, stderr = client.exec_command(
                f"chmod {args.mode} '{args.remote}'", timeout=args.timeout
            )
            exit_code = stdout.channel.recv_exit_status()
            err = stderr.read().decode("utf-8", errors="replace")
            if exit_code != 0:
                raise SystemExit(err or f"Failed to chmod {args.remote}")

        _, stdout, stderr = client.exec_command(
            f"wc -c < '{args.remote}'", timeout=args.timeout
        )
        exit_code = stdout.channel.recv_exit_status()
        err = stderr.read().decode("utf-8", errors="replace")
        if exit_code != 0:
            raise SystemExit(err or f"Failed to stat {args.remote}")
        size_text = stdout.read().decode("utf-8", errors="replace").strip()
        size = int(size_text) if size_text.isdigit() else -1
        sys.stdout.write(
            f"uploaded {args.local} -> {args.remote} ({size} bytes)\n"
        )
        return 0
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password")
    default_port = int(os.environ.get("ROUTER_SSH_PORT") or 22)
    parser.add_argument("--ssh-port", type=int, default=default_port)
    parser.add_argument("--timeout", type=int, default=15)

    subparsers = parser.add_subparsers(dest="action", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--command")
    run_parser.add_argument("--stdin", action="store_true")

    upload_parser = subparsers.add_parser("upload")
    upload_parser.add_argument("--local", required=True)
    upload_parser.add_argument("--remote", required=True)
    upload_parser.add_argument("--mode")

    args = parser.parse_args()
    if args.action == "run":
        return run_command(args)
    if args.action == "upload":
        return upload_file(args)
    raise SystemExit(f"Unsupported action: {args.action}")


if __name__ == "__main__":
    raise SystemExit(main())
