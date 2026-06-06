#!/usr/bin/env python3
"""
Opencode PTY Wrapper

Runs opencode inside a pseudo-TTY (required for tool access),
reads the prompt from a file (to avoid command-line length limits),
and extracts the assistant's text response.
"""

import argparse
import os
import pty
import re
import select
import sys


def strip_ansi(text):
    ansi_escape = re.compile(r'\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def run_opencode(prompt, model, timeout_sec=300):
    master_fd, slave_fd = pty.openpty()
    pid = os.fork()

    if pid == 0:
        # Child: set up the slave as stdin/stdout/stderr
        os.close(master_fd)
        os.setsid()
        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)
        if slave_fd > 2:
            os.close(slave_fd)

        # Execute opencode
        os.execvp("opencode", ["opencode", "run", prompt, "--model", model])
        os._exit(1)

    # Parent: read from master_fd with timeout
    os.close(slave_fd)
    output = []

    try:
        import time
        start = time.time()
        while True:
            elapsed = time.time() - start
            remaining = timeout_sec - elapsed
            if remaining <= 0:
                break

            ready, _, _ = select.select([master_fd], [], [], max(0, remaining))
            if not ready:
                break

            try:
                data = os.read(master_fd, 8192)
                if not data:
                    break
                output.append(data.decode('utf-8', errors='replace'))
            except OSError:
                break
    finally:
        os.close(master_fd)
        # Kill child if still running
        try:
            os.kill(pid, 15)  # SIGTERM
            os.waitpid(pid, 0)
        except ProcessLookupError:
            pass

    return ''.join(output)


def extract_text(full_output):
    clean = strip_ansi(full_output)
    lines = clean.split('\n')
    response_lines = []
    found_header = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith('Script started') or stripped.startswith('Script done'):
            continue
        if 'COMMAND=' in stripped and 'COMMAND_EXIT_CODE=' not in stripped:
            continue
        if stripped.startswith('COMMAND_EXIT_CODE='):
            continue
        if '·' in line and any(name in line for name in ['deepseek', 'nemotron', 'minimax', 'mimo']):
            found_header = True
            continue
        if found_header:
            if stripped.startswith('>') or stripped.startswith('$'):
                continue
            response_lines.append(stripped)

    return '\n'.join(response_lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prompt-file', required=True, help='File containing the prompt')
    parser.add_argument('--model', required=True, help='Model to use')
    parser.add_argument('--timeout', type=int, default=300, help='Timeout in seconds')
    args = parser.parse_args()

    with open(args.prompt_file, 'r', encoding='utf-8') as f:
        prompt = f.read()

    full_output = run_opencode(prompt, args.model, args.timeout)
    text = extract_text(full_output)

    if not text.strip():
        print("Error: No assistant text found", file=sys.stderr)
        sys.exit(1)

    print(text)


if __name__ == '__main__':
    main()
