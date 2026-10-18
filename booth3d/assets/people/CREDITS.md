# The rigged people: credits

Everything here is CC0 (public domain), or made for Name City. Credit is
given anyway.

## Bodies and clothes: MakeHuman (CC0)

The people are built in Blender with MPFB 2, the MakeHuman plugin, by
`tool/blender/humans.py`. MPFB itself is GPL. It's a tool only and none of
its code ships. The assets come from MakeHuman's CC0 asset packs
(makehumancommunity.org, "asset packs", the `_cc0` downloads).

- **Bodies:**
  - the MakeHuman base mesh;
  - its low-poly proxies `male1591` and `female1605`;
  - MPFB's "game engine" skeleton.

  All are MakeHuman system assets. Every body's head is removed: from the
  neck up, everyone wears the city's own simple head.
- **MakeHuman system assets** (the MakeHuman team):
  - `male_casualsuit03`, `male_casualsuit06`, `female_casualsuit01`,
    `female_elegantsuit01`;
  - `shoes01` to `shoes06`.
- **By MRT ("toigo"):**
  - `toigo_male_suit_3`, `toigo_male_double-breasted_suit`,
    `toigo_male_suit_tie_and_jacket`;
  - `toigo_female_suit`, `toigo_female_double-breasted_suit`;
  - `toigo_fisherman_sweater`, `toigo_wool_pants`, `toigo_long_full_skirt`,
    `toigo_shift_dress`;
  - `toigo_ankle_boots_male`, `toigo_ankle_boots_female`,
    `toigo_mj_cloth_shoes`, `toigo_gloves_short`.
- **Other authors:**
  - `namuhekam_male_polo_shirt` by Namuhekam;
  - `elvs_crude_t-shirt_male` (MakeHuman's, edited by Elvaerwyn);
  - `joepal_crude_t-shirt_female` by Joel Palmius;
  - `cortu_cargo_pants` by cortu (the CC0 "Pants 01" pack).

The crew's hi-vis vests and their reflective tape are cut from each
worker's own shirt by `humans.py`. The Glyph Works' makers' lab coats are
`toigo_female_suit` (its jacket and skirt, white: a coat to the knee) over
`toigo_wool_pants`, cut off under its hem by `humans.py`. The garments' photographed cloth is
packed into one texture, `atlas.jpg` and `atlas_normal.jpg`, by
`tool/blender/people_atlas.py`. The plain garments are made grey there so
each person's colour can be applied in the app.

## Motion: Quaternius' Universal Animation Library 1 and 2 (CC0)

The clips are by Quaternius (quaternius.com; also on opengameart.org). They
are retargeted onto the skeleton by `tool/blender/motions.py`, and only the
bones' turns and the hips' travel are kept (`tool/blender/strip_channels.py`).

| Clip | Source |
|---|---|
| idle | Idle_Loop |
| talk | Idle_Talking_Loop |
| walk | Walk_Loop |
| walk_formal | Walk_Formal_Loop |
| jog | Jog_Fwd_Loop |
| interact | Interact |
| pick_up | PickUp_Table |
| push | Push_Loop |
| kneel_fix | Fixing_Kneeling |
| sit | Sitting_Idle_Loop |
| sit_talk | Sitting_Talking_Loop |
| arms_folded | Idle_FoldArms_Loop |
| phone | Idle_TalkingPhone_Loop |
| no | Idle_No_Loop |
| yes | Yes |
| walk_carry | Walk_Carry_Loop |
| hammer | TreeChopping_Loop |
| drink | Consume |

## Made for Name City

- **The head:** the head, its one simple face, the hair, and the hard hats
  and caps (`assets/models/people.glb`, `tool/blender/people.py`).
- **How it moves:** posing the people as the city's own figures are posed
  (`lib/world/rig.dart`).
