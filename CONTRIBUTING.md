# Contributing to GitHub Ready

Thank you for considering contributing to GitHub Ready.

## Before contributing

- Search existing issues before opening a new one.
- Use the appropriate issue template for bug reports or feature requests.
- Do not include access tokens, private keys, passwords, account details, or other sensitive information.
- Keep changes focused and avoid unrelated refactoring.

## Development requirements

- macOS 13 or later
- Swift 6
- Git
- GitHub CLI

## Local verification

Before submitting a pull request, run:

```bash
swift test
swift build
./script/build_and_run.sh verify
