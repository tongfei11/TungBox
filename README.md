# TungBox

Current version: `0.1.0(0024)`

TungBox is a small macOS wrapper for running `sing-box` configurations.

It currently supports:

- Multiple JSON configuration profiles.
- Import, edit, save, and delete profiles.
- Subscription URLs that refresh into profiles, with native sing-box JSON handled directly.
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

Subscriptions are stored in the same directory as `subscriptions.json`. Refreshing a subscription creates or updates a profile named `订阅 - <name>`.

## Notes

TUN mode on macOS usually needs elevated permissions or a signed Network Extension. This MVP starts the official `sing-box` binary as the current user, so local mixed/SOCKS proxy configs work best for the first version.
