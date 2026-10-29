# ArticulationBox user guide

**English** · [Русский](USER_GUIDE_RU.md) · [Repository](https://github.com/andreynovikov86-cmd/ArticulationBox)

Open **Help** in the field's full menu for short explanations without an internet connection. The quick menu contains ready articulation choices and saved independent Controller presets. The full menu keeps these choices under Articulations to remain short with large banks.

## 1. Quick start

1. Open a MIDI item and keep Articulation_Manager.lua running.
2. Create a bank: Settings > Banks > New.
3. Add / Edit articulation: configure mappings in one window. Use Save & Next to build a bank quickly.
4. Select musical notes, open the field menu and choose an articulation.
5. Optional: Settings > Default articulation for notes without an override.
6. Save the REAPER project.

Assign Articulation_Quick_Menu.lua to a MIDI Editor shortcut for ready articulation and controller choices at the mouse cursor.

## 2. Articulations and defaults

Channel: routes musical notes to a channel.
Keyswitch: sends a MIDI note that selects a sound in your instrument.
KS + Channel: combines both methods.

Add / Edit articulation opens one compact parameter window. Bank shows the destination. Articulation selects Add New or a saved mapping. New names start empty. Add variant copies the selected settings into a new mapping, leaving the original intact. Remove articulation deletes the selected mapping from this bank, preserving existing MIDI assignments. Keyswitch, Channel and KS + Channel show their relevant parameters and can include a linked Controller. The fourth type, Controller, saves an independent preset. Channel sets the musical-note channel; KS channel sets the keyswitch channel. KS channel 0 uses the musical note's channel.

Playing a MIDI key or clicking a piano-roll key automatically fills KS note and velocity. A mapped key also loads its saved name and parameters; an exact velocity match selects that variant. An unmapped key switches to Add New with an empty name, so the previous mapping is kept. Both values remain editable. Save stores changes without closing the window. Save & Next stores the current mapping and always switches to Add New with an empty name and the current parameters. The last saved name stays visible. Piano-roll row names update immediately after every save. Cancel discards only the current unsaved entry. Resize the window by its edges; its size is remembered.

Mappings on the same keyswitch pitch and routing with different velocities are grouped in a submenu. Variants are sorted from higher to lower velocity; the highest-velocity name labels the group. Each variant keeps its own name and velocity.

Select notes and choose a name to apply it. Clear articulation removes the explicit override; a configured default can apply again. Defaults require a keyswitch mapping.

The field shows the selected articulation, Mixed for different assignments, or a dash if none is assigned. With no notes selected, it shows the default name, if configured.

## 3. Banks and saving

Banks selects the current track's bank. Settings > Banks creates, renames, removes, imports or exports banks. Export saves all banks of the current track.

Track banks are independent. New tracks start with Empty bank; saved bank templates remain available. Bank and articulation edits are saved automatically. Save the project to retain track bank choices and note assignments.

Appearance and common playback preferences persist between REAPER sessions. Timing changes also update the current bank's mappings.

Removing a bank or mapping does not erase existing MIDI assignments. Use Clear articulation on notes when you want to remove their overrides.

## 4. Manual keyswitches

Draw or edit notes directly on mapped articulation rows. They are treated as manual switches and do not receive a default articulation. Their last switch remains active until another manual switch or an explicit automatic assignment on that MIDI channel.

A later switch shortens the earlier keyswitch at its start. Different switches at exactly the same time on one channel remain ambiguous.

Independently editing an automatic keyswitch's pitch, position, length or velocity makes it manual and removes its former automatic links. Musical notes are preserved. Move the musical note instead to keep an automatic link.

## 5. Playback and timing

Trigger chooses Before note start or After note start. Delay (ms) sets the distance in milliseconds; Trigger chooses which side of the note start it applies to. Automatic keyswitches end with their musical notes, or sooner if another switch intervenes. Length/Overlap are legacy compatibility values.

For a loop ending, use After note start and a suitable Delay. KS velocity is independent of musical velocity: a chord with velocity 1 can trigger a keyswitch with velocity 100. The script preserves the chord velocity. MIDI tick resolution can impose a minimum delay.

Keyswitch timing updates the current bank and its assignments in the active take, preserving each mapping's Before/After direction; new articulations use the saved timing defaults.

Chase MIDI note-ons enables REAPER's option to resend sustained notes when playback starts inside them. Test the result with your instrument.

Auto-stagger conflicting notes delays conflicting musical starts slightly and shortens notes by the same amount, keeping their ends fixed. Spacing sets the delay in ms. It does not provide independent simultaneous articulations on one MIDI channel.

## 6. Editing and transposition

Keep the main script running while editing. Moving or resizing musical notes updates their linked automatic keyswitches. Returning notes to the same articulation can restore starts previously delayed by auto-stagger.

At the item start, or with auto-stagger enabled when neighboring starts leave no MIDI tick for a switch, a musical note can move slightly later to leave room for a Before keyswitch; its end stays fixed. After keyswitches do not require this advance space.

Broad selection/transposition protects keyswitch pitches while musical notes change pitch. With item/take pitch changes, the script writes the transpose into musical notes and resets the take pitch control, so the P+ value may disappear.

Use REAPER Undo to reverse an edit. Protection and following require the running main script.

## 7. Tools and troubleshooting

Name keyswitch rows labels piano-roll rows from the bank.
Refresh keyswitches rebuilds automatic switches in the active take from assignments.
Clear missing keyswitch assignments removes stale links after switches were deleted; a default may then apply.
Legacy keyswitches > Find for review selects possible older switches. Review the selection before Remove reviewed; manual switches can match too.
Status shows the latest operation message.

The parameter editor requires ReaImGui, installed through ReaPack. Restart REAPER after installing the extension.

No sounds change: check the instrument mapping, MIDI channel and velocity. Empty menu: choose this track's bank and add mappings. An articulation-only menu has no settings: use the field or Articulation_Menu_Popup.lua for Help and Settings.

## 8. Field, actions and startup

Articulation_Manager.lua runs the embedded field and background updates.
Articulation_Quick_Menu.lua opens only articulations at the mouse cursor.
Articulation_Menu_Popup.lua opens the full menu.

Lock position prevents moving/resizing the field. Turn it off to drag the field or its edges. Appearance and position also offers numeric position, size and font settings.
Run script on startup starts the main script with REAPER. Close field stops it for this session; disable startup separately if needed.

Detailed English and Russian guides are included as USER_GUIDE.md and USER_GUIDE_RU.md beside the scripts and linked from the GitHub README.

## Articulation parameters

| Field | Meaning |
| --- | --- |
| Name | The label shown in the articulation menu and on keyswitch rows. |
| Channel | Destination channel for musical notes (1–16), used by channel-based mappings. |
| KS note | MIDI note number (0–127) required by the instrument. New mappings use the active piano-roll row; the open editor also learns new MIDI note-ons or piano-roll key clicks; the number avoids octave-label differences between instruments. |
| KS velocity | Keyswitch velocity (1–127). Some libraries use velocity to select a variant. |
| Trigger | Before note start or After note start. |
| Delay (ms) | Timing distance from the musical-note start. MIDI tick resolution, available item space and neighboring switches can limit this. |
| KS channel | Channel used for the keyswitch. 0 follows the musical note's channel; 1–16 chooses an explicit channel. |

Mappings are listed by descending KS pitch: higher pitches appear first. A checkmark identifies an articulation used by selected notes; when a selection is mixed, note counts indicate how many notes use each entry. Changing a bank mapping does not rewrite every old assignment in every item: existing assignments keep their saved mapping. Reapply the articulation to selected notes to use a revised pitch/channel mapping. The timing tool can refresh current-bank timings in the active take.

## Menu reference

| Menu item | What it does |
| --- | --- |
| Clear articulation | Removes the explicit assignment from selected musical notes. A configured default can apply again. |
| Add / Edit articulation | Opens the bank’s parameter window. Select Add New to add, or select a saved entry to edit. Remove articulation inside the window deletes the selected mapping while preserving existing MIDI assignments. |
| Articulations | Opens the bank’s articulation choices. Velocity variants on the same KS pitch and routing are grouped in submenus. The shortcut quick menu opens choices directly. |
| Banks | Selects the active bank for this track. |
| Settings > Banks > New / Rename / Remove | Manages bank mappings. Other tracks retain independent copies. |
| Settings > Banks > Import / Export | Imports a bank file or exports all banks of the current track. Keep exported files as backups. |
| Settings > Appearance and position > Field position | Sets the horizontal position and bottom margin in the MIDI editor. |
| Settings > Appearance and position > Size and font | Sets field width, height and font size. |
| Settings > Legacy keyswitches > Find for review | Selects possible switches created before managed ownership markers; review them first. |
| Settings > Legacy keyswitches > Remove reviewed | Deletes the reviewed selection only after the script's safety checks. |
| Settings > Name keyswitch rows | Adds articulation names to mapped piano-roll rows. |
| Settings > Default articulation | Selects the fallback keyswitch articulation or disables it with None. Channel-only mappings cannot be defaults. |
| Settings > Keyswitch timing | Sets timing distance/compatibility length for current-bank mappings, keeping each mapping’s Before/After direction, refreshes their assignments in the active take, and saves defaults for new mappings. Overlap is retained for compatibility with older timing behavior. |
| Settings > Chase MIDI note-ons | Toggles REAPER's note-chase option for starting playback inside sustained MIDI notes. |
| Settings > Auto-stagger conflicting notes | Enables small start delays to resolve different automatic articulations at one onset/channel. Ends stay fixed. |
| Settings > Auto-stagger spacing | Sets the delay between conflicting starts (0.1–50 ms). MIDI tick resolution can impose a larger minimum. |
| Settings > Clear missing keyswitch assignments | Clears assignments whose managed switches are missing. A default may apply afterward. |
| Settings > Refresh keyswitches | Rebuilds automatic switches in the active take from stored assignments. |
| Settings > Status | Shows the latest operation result or error. |
| Settings > Run script on startup | Toggles automatic startup with REAPER. |
| Settings > Close field | Stops the main script for this session. |
| Help | Opens the built-in help topics and current status. |
| Lock position | Prevents dragging or resizing the embedded field. |

## Example: a delayed ending

Choose **Keyswitch**, set **Trigger > After note start**, then enter **Delay (ms)** and the instrument’s required KS note and velocity. For example, a chord at velocity 1 can send an ending keyswitch at velocity 100, 1 ms after the chord starts. The chord velocity is preserved. Automatic keyswitches follow the musical note’s end; a later switch can shorten them. If the delay exceeds the note duration, the switch uses the minimum one-tick length inside the item.

For MIDI input, the editor reads incoming note-on pitch and velocity. Piano-roll key clicks use the active row and REAPER’s default note velocity. Captured values remain editable until another key is played. Learning does not insert or record notes.

**Save** keeps the window open. **Save & Next** saves the current mapping and always selects **Add New**, clearing the name and retaining the other parameters. The saved name remains visible. **Add variant** starts a new mapping with copied parameters and an empty name. Piano-roll names refresh immediately after each save. Closing the editor discards only the current unsaved entry; earlier entries stay saved.

## Example: a default and an exception

Choose your sustained articulation under **Settings > Default articulation**. Select a few musical notes and apply Staccato. Notes without an explicit override use the default again at their starts, except where a manually drawn switch intentionally controls the channel. A default cannot provide a different simultaneous sound to another note on the same channel: use suitable instrument routing or auto-stagger where appropriate.

Automatic following, default maintenance, overlap trimming and pitch protection require the main script to remain running. Save projects and export banks before transferring your setup to another computer.

## Controllers

Choose Controller in Add / Edit articulation to save a named, independent preset. It appears under Controller in the full and quick menus. This submenu is also available to reset controllers linked to articulations or assigned to selected notes. Applying it preserves the selected notes' articulation. Other articulation types can include a linked Controller; choose None to leave it disabled.

The chooser starts with Pitch Bend, Mod Wheel (CC 1) and Hold Pedal (CC 64), followed by the other CC numbers. CC values range from 0 to 127. Pitch Bend ranges from -8192 to 8191, with 0 at center. Hold Pedal normally uses 127 to hold and reset 0 to release.

Length: Full note sets the value before note-on and resets after note-off. Note start makes a short pulse across note-on. Note end sets the value while the note is still held and resets after note-off. Before and After set these margins in milliseconds, with at least one MIDI tick on either side. Reset value is the value sent at the end. Control channel 0 follows the musical note's channel.

Controllers follow musical note moves and length edits while the manager runs. At the item start, a note may move slightly later to leave room; at the end, the item may extend to play the reset. Undo/Redo keeps these changes together.

Controllers affect every sounding voice on their MIDI channel. Overlapping notes cannot have independent controller states on the same channel. A later assignment on the same controller lane replaces its earlier state. An independent preset overrides a linked controller on that lane until the articulation is applied again. Other controller lanes remain assigned.

**Controller > Reset controllers** removes all controller assignments from selected notes while preserving their articulation. It is disabled when no selected notes have controllers. Settings > Clear controller assignments provides the same operation. Removing a preset from the bank preserves existing MIDI assignments. Controller presets are saved with this track's bank.
