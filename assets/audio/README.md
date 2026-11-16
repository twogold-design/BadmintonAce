# Match sound effects

User-supplied samples from `20261029_GO`: `SFX_Cheer_a.opus`,
`SFX_Cheer_b.opus`, `SFX_Cheer_c.opus`, `SFX_Win.opus`, and `SFX_Lose.opus`.

The game uses Ogg Vorbis copies (48 kHz stereo, quality 5), converted with
FFmpeg using `-c:a libvorbis -q:a 5`. The complete samples are retained without
trimming, normalization, or looping. The original supplied files are unchanged.

Each point randomly selects one cheer. A separate player prevents hit sounds
from cutting it off. Match results play the win or lose sample once according
to the local player's result and stop any remaining point cheer. Shared-screen
local matches celebrate the winner with the win sample. Rematching or leaving the game stops both players;
the sound setting and match pause also apply.
