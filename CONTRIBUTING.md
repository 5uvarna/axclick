# Contributing to axclick

Bug reports, fixes and support for apps that don't label well are all welcome.

## Building

```bash
./build.sh            # builds build/axclick.app and build/axclick
./build.sh install    # also installs the app to ~/Applications and restarts it
```

Each build is signed ad hoc, so after a rebuild turn axclick off and on again in
System Settings → Privacy & Security → Accessibility.

## Contributor license terms

axclick is released under the GNU GPL v3. The maintainer also distributes
official signed builds, and may release axclick under other license terms in the
future. To keep that possible, every contribution has to come with these terms:

By submitting a contribution (a pull request, patch or other code) to this
repository, you confirm that:

1. You wrote the contribution, or otherwise have the right to submit it.
2. You license the contribution to the public under the GNU GPL v3, the same as
   the rest of axclick.
3. You also grant the maintainer of axclick a perpetual, worldwide,
   non-exclusive, royalty-free, irrevocable license to use, modify, sublicense
   and distribute your contribution under any license terms, including
   proprietary ones.

You keep the copyright in your contribution. If you don't agree to these terms,
please open an issue describing the change instead of sending code.
