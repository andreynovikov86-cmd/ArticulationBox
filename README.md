# ArticulationBox

By **Andrey Novikov**.

**English** · [Русский](README_RU.md)

User guide: [English](ArticulationBox/USER_GUIDE.md) · [Русский](ArticulationBox/USER_GUIDE_RU.md). Open **Help** in the full script menu for offline explanations.

A compact articulation menu for the REAPER MIDI Editor.

One ReaPack package includes the embedded articulation field, a quick menu at the mouse cursor, and a full settings menu. It supports manual and automatic keyswitches, MIDI channel switching, independent track banks, default articulations, keyswitches that follow musical notes, and keyswitch pitch protection during transposition. The script interface is in English.

## Install with ReaPack

Import this repository URL:

```text
https://raw.githubusercontent.com/andreynovikov86-cmd/ArticulationBox/main/index.xml
```

In REAPER, open **Extensions > ReaPack > Import repositories** and paste the URL. Then open **Browse packages**, find **ArticulationBox**, choose **Install**, and click **Apply**.

The script requires [js_ReaScriptAPI](https://github.com/juliansader/ReaExtensions) and [ReaImGui](https://github.com/cfillion/reaimgui) for the parameter editor. Install both separately through ReaPack and restart REAPER after installing the extensions.

## First run

Open a MIDI item. In **Actions > MIDI Editor**, run `Articulation_Manager.lua`. Assign a shortcut to `Articulation_Quick_Menu.lua` in the same action section for quick articulation selection. Keep the main script running so it can update linked keyswitches.

Create a bank through **Settings > Banks > New** and add entries through **Add / Edit articulation**. Enable **Settings > Run script on startup** for automatic startup. Save your project to restore track bank choices and note assignments.

Personal banks, projects, and user backups are not included in this repository. When moving from a manual installation to ReaPack, reassign your shortcuts to the actions from the new installation.

For a full installation guide in Russian, see [INSTALL_RU](ArticulationBox/INSTALL_RU.txt). Third-party code acknowledgments are in [THIRD_PARTY_NOTICES](ArticulationBox/THIRD_PARTY_NOTICES.txt).

## Articulation editor

Add / Edit articulation uses one compact, resizable window with **Keyswitch**, **Channel**, and **KS + Channel** choices. Play a MIDI key or click a piano-roll key to fill the keyswitch note and velocity, then edit either value if needed. **Save & Next** builds several mappings without reopening the editor. Window size is remembered. The Bank line identifies the destination; the Articulation list selects a new or saved mapping, and Remove articulation deletes a saved mapping. Full-menu choices live under Articulations; same-pitch velocity variants have their own submenus. The shortcut still opens choices directly.

Choose **Before note start** or **After note start** and set Delay in milliseconds. A delayed keyswitch can trigger a loop ending after a chord starts, with independent keyswitch velocity. Automatic keyswitches still follow the musical note’s end.

## Manual keyswitches

You can draw and edit MIDI notes directly on articulation rows. These notes do not receive a default articulation. Their latest switch remains active until the next explicit automatic assignment on the same MIDI channel.

If you independently change an automatic keyswitch's pitch, position, length, or velocity, it becomes manual. Its previous automatic assignments are removed while the musical notes are preserved. Moving musical notes still moves their linked automatic keyswitches.

When a later keyswitch starts on the same MIDI channel, the earlier keyswitch is shortened to end at that point. Musical note lengths are preserved.

## Updates

To install updates, use **Extensions > ReaPack > Synchronize packages**.

To publish a new release, change the package code, increase `@version` in `ArticulationBox/Articulation_Manager.lua`, update `@changelog`, and push to `main`. The workflow uses the [official ReaPack indexer](https://github.com/cfillion/reapack-index). Existing indexed versions are retained, and download links refer to fixed commits.

## License

ArticulationBox is licensed under the [MIT License](LICENSE.md), which permits use, modification and redistribution, including commercial use, with the required copyright and license notices.

Adapted Gridbox code retains its original MIT copyright and license notice in [THIRD_PARTY_NOTICES](ArticulationBox/THIRD_PARTY_NOTICES.txt). Both notices are included in the ReaPack package.
