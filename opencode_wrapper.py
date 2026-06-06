#!/usr/bin/env python3
"""
Opencode TTY Wrapper

Uses the `script` command to force a pseudo-TTY for opencode run,
then extracts the assistant's text response from the captured output.
This is necessary because opencode run requires interactive TTY mode
to produce model responses, but subshells and pipes break TTY detection.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile


def strip_ansi(text):
    """Remove ANSI escape codes from text."""
    ansi_escape = re.compile(r'\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def extract_assistant_text(clean_output):
    """Extract the assistant's text response from the captured output."""
    lines = clean_output.split('\n')
    response_lines = []
    found_header = False
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        # Skip script command header/footer
        if stripped.startswith('Script started'):
            continue
        if stripped.startswith('Script done'):
            break
        if 'COMMAND=' in stripped and 'COMMAND_EXIT_CODE=' not in stripped:
            continue
        if stripped.startswith('COMMAND_EXIT_CODE='):
            continue
        # Detect model header
        if '·' in line and any(name in line for name in ['build', 'deepseek', 'nemotron', 'minimax', 'mimo']):
            found_header = True
            continue
        if found_header:
            response_lines.append(stripped)
    
    return '\n'.join(response_lines) if response_lines else clean_output.strip()


def run_opencode_via_script(prompt, model, timeout_sec=1800):
    """Run opencode using the `script` command to get a pseudo-TTY."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        typescript_file = f.name
    
    try:
        escaped_prompt = prompt.replace('"', '\\"')
        opencode_cmd = f'opencode run "{escaped_prompt}" --model "{model}" --no-replay'

        result = subprocess.run(
            ['script', '-q', '-c', opencode_cmd, typescript_file],
            capture_output=True,
            text=True,
            timeout=timeout_sec
        )
        
        with open(typescript_file, 'r', encoding='utf-8', errors='replace') as f:
            raw_output = f.read()
        
        clean_output = strip_ansi(raw_output)
        assistant_text = extract_assistant_text(clean_output)
        
        return assistant_text, result.returncode
    
    finally:
        try:
            os.unlink(typescript_file)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description='Run opencode with pseudo-TTY and extract text output')
    parser.add_argument('prompt', help='The prompt to send to opencode')
    parser.add_argument('--model', required=True, help='The model to use')
    parser.add_argument('--timeout', type=int, default=1800, help='Timeout in seconds (default: 1800 = 30min)')
    args = parser.parse_args()

    assistant_text, exit_code = run_opencode_via_script(args.prompt, args.model, args.timeout)

    if exit_code != 0:
        print(f"Error: opencode exited with code {exit_code}", file=sys.stderr)
        sys.exit(exit_code)

    if not assistant_text.strip():
        print("Error: No assistant text found in output", file=sys.stderr)
        sys.exit(1)

    print(assistant_text)


if __name__ == '__main__':
    main()

