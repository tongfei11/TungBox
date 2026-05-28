# TungBox

TungBox is a small macOS wrapper for running `sing-box` configurations.

It currently supports:

- Multiple JSON configuration profiles.
- Import, edit, save, and delete profiles.
- `sing-box check -c ...` validation.
- Start and stop `sing-box run -c ...`.
- Live process logs.

## Run

Install sing-box first:

```bash
brew install sing-box
```

Then run the app:

```bash
swift run TungBox
```

Profiles are stored in:

```text
~/Library/Application Support/TungBox
```

## Notes

TUN mode on macOS usually needs elevated permissions or a signed Network Extension. This MVP starts the official `sing-box` binary as the current user, so local mixed/SOCKS proxy configs work best for the first version.
