# ArticulationBox user guide

**English** · [Русский](USER_GUIDE_RU.md) · [Repository](https://github.com/andreynovikov86-cmd/ArticulationBox)

Open **Help** in the field's full menu for short explanations without an internet connection. The quick articulation menu intentionally contains only articulation choices.

## 1. Quick start

1. Open a MIDI item and keep Articulation_Manager.lua running.
2. Create a bank: Settings > Banks > New.
3. Add articulation: choose the switching method and enter your instrument's mapping.
4. Select musical notes, open the field menu and choose an articulation.
5. Optional: Settings > Default articulation for notes without an override.
6. Save the REAPER project.

Assign Articulation_Quick_Menu.lua to a MIDI Editor shortcut for an articulation-only menu at the mouse cursor.

## 2. Articulations and defaults

MIDI channel: routes musical notes to a channel.
Keyswitch: sends a MIDI note that selects a sound in your instrument.
Channel + keyswitch: combines both methods.

Use the pitch, velocity and channels required by your instrument. KS channel 0 means the musical note's channel. New KS pitch uses the active piano-roll row.

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

Automatic keyswitches start before their musical notes and follow their length, ending sooner if another switch intervenes. Lead time controls the advance. Length and Overlap fields are retained for compatibility; they do not set the final duration in Follow musical note behavior.

Keyswitch timing updates the current bank and its assignments in the active take; new articulations use the saved timing defaults.

Chase MIDI note-ons enables REAPER's option to resend sustained notes when playback starts inside them. Test the result with your instrument.

Auto-stagger conflicting notes delays conflicting musical starts slightly and shortens notes by the same amount, keeping their ends fixed. Spacing sets the delay in ms. It does not provide independent simultaneous articulations on one MIDI channel.

## 6. Editing and transposition

Keep the main script running while editing. Moving or resizing musical notes updates their linked automatic keyswitches. Returning notes to the same articulation can restore starts previously delayed by auto-stagger.

At the item start, a musical note can move slightly later to leave room for its keyswitch; its end stays fixed.

Broad selection/transposition protects keyswitch pitches while musical notes change pitch. With item/take pitch changes, the script writes the transpose into musical notes and resets the take pitch control, so the P+ value may disappear.

Use REAPER Undo to reverse an edit. Protection and following require the running main script.

## 7. Tools and troubleshooting

Name keyswitch rows labels piano-roll rows from the bank.
Refresh keyswitches rebuilds automatic switches in the active take from assignments.
Clear missing keyswitch assignments removes stale links after switches were deleted; a default may then apply.
Legacy keyswitches > Find for review selects possible older switches. Review the selection before Remove reviewed; manual switches can match too.
Status shows the latest operation message.

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
| MIDI channel / Note channel | Destination channel for musical notes (1–16), used by channel-based mappings. |
| KS pitch | MIDI note number (0–127) required by the instrument. New mappings use the active piano-roll row; the number avoids octave-label differences between instruments. |
| Velocity | Keyswitch velocity (1–127). Some libraries use velocity to select a variant. |
| Lead time | How many milliseconds before the musical note the keyswitch should start. Available item space and neighboring notes can limit this. |
| Length | Retained for compatibility. Automatic switches currently always follow musical notes. |
| KS channel | Channel used for the keyswitch. 0 follows the musical note's channel; 1–16 chooses an explicit channel. |

Mappings are listed by descending KS pitch: higher pitches appear first. A checkmark identifies an articulation used by selected notes; when a selection is mixed, note counts indicate how many notes use each entry. Changing a bank mapping does not rewrite every old assignment in every item: existing assignments keep their saved mapping. Reapply the articulation to selected notes to use a revised pitch/channel mapping. The timing tool can refresh current-bank timings in the active take.

## Menu reference

| Menu item | What it does |
| --- | --- |
| Clear articulation | Removes the explicit assignment from selected musical notes. A configured default can apply again. |
| Add articulation | Creates a mapping in the current bank. Adding to Empty bank creates a saved New bank. |
| Edit articulation | Lets you choose and edit a mapping in the current bank. |
| Remove articulation | Removes a mapping from the current bank, preserving existing MIDI assignments. |
| Articulation names | Apply the chosen mapping to selected musical notes. |
| Banks | Selects the active bank for this track. |
| Settings > Banks > New / Rename / Remove | Manages bank mappings. Other tracks retain independent copies. |
| Settings > Banks > Import / Export | Imports a bank file or exports all banks of the current track. Keep exported files as backups. |
| Settings > Appearance and position > Field position | Sets the horizontal position and bottom margin in the MIDI editor. |
| Settings > Appearance and position > Size and font | Sets field width, height and font size. |
| Settings > Legacy keyswitches > Find for review | Selects possible switches created before managed ownership markers; review them first. |
| Settings > Legacy keyswitches > Remove reviewed | Deletes the reviewed selection only after the script's safety checks. |
| Settings > Name keyswitch rows | Adds articulation names to mapped piano-roll rows. |
| Settings > Default articulation | Selects the fallback keyswitch articulation or disables it with None. Channel-only mappings cannot be defaults. |
| Settings > Keyswitch timing | Sets lead/compatibility length for current-bank mappings, refreshes their assignments in the active take, and saves defaults for new mappings. Overlap is retained for compatibility with older timing behavior. |
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

## Example: a default and an exception

Choose your sustained articulation under **Settings > Default articulation**. Select a few musical notes and apply Staccato. Notes without an explicit override use the default again at their starts, except where a manually drawn switch intentionally controls the channel. A default cannot provide a different simultaneous sound to another note on the same channel: use suitable instrument routing or auto-stagger where appropriate.

Automatic following, default maintenance, overlap trimming and pitch protection require the main script to remain running. Save projects and export banks before transferring your setup to another computer.
